// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// e11: MetalFX spatial upscaling of the stream (MTLFXSpatialScaler, macOS 13+).
//
// Per frame, all on the GPU except the final copy:
//   decoded NV12 --VTPixelTransfer--> BGRA (w x h) --MetalFX spatial--> BGRA (2w x 2h)
//   --VTPixelTransfer--> NV12 (2w x 2h) --copy--> AVFrame for the renderer.
// The decoder's buffer is only read, never kept. Compiled without ARC.

#include "macMetalFXUpscale.h"

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>
#import <VideoToolbox/VideoToolbox.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>

extern "C" {
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixfmt.h>
}

static std::atomic<bool> g_enabled{false};
static std::atomic<bool> g_failed{false};
static std::atomic<bool> g_reset_requested{false};
static std::atomic<int> g_active{0};
static std::atomic<double> g_last_ms{0.0};
static std::atomic<int> g_out_w{0}, g_out_h{0};
static std::atomic<int> g_target_w{0}, g_target_h{0};
static std::atomic<double> g_p95_ms{0.0};

namespace {

struct State {
	id<MTLDevice> device = nil;
	id<MTLCommandQueue> queue = nil;
	id<MTLFXSpatialScaler> scaler = nil;
	CVMetalTextureCacheRef tex_cache = nullptr;
	VTPixelTransferSessionRef transfer = nullptr;
	CVPixelBufferPoolRef in_pool = nullptr;   // BGRA w x h
	CVPixelBufferPoolRef out_pool = nullptr;  // BGRA 2w x 2h
	CVPixelBufferPoolRef nv12_pool = nullptr; // NV12 2w x 2h
	int width = 0, height = 0, out_w = 0, out_h = 0;
	double avg_ms = 0.0;
	int frames = 0;
	double recent[120] = {};
	int recent_n = 0, recent_i = 0;
	int slow_windows = 0;
};

// Output size for an input of w x h: fit the shown size, keep the aspect ratio, at most 2x,
// even dimensions. Returns false when the gain would be too small to be worth it.
bool OutputSizeFor(int w, int h, int &ow, int &oh)
{
	double scale = 2.0;
	const int tw = g_target_w.load(), th = g_target_h.load();
	if (tw > 0 && th > 0)
		scale = std::min(2.0, std::min((double)tw / w, (double)th / h));
	if (scale < 1.1)
		return false; // the screen isn't much bigger than the stream: nothing to gain
	ow = ((int)(w * scale)) & ~1;
	oh = ((int)(h * scale)) & ~1;
	return ow > w && oh > h;
}

State g;

void Teardown()
{
	if (g.scaler) { [g.scaler release]; g.scaler = nil; }
	if (g.queue) { [g.queue release]; g.queue = nil; }
	if (g.device) { [g.device release]; g.device = nil; }
	if (g.tex_cache) { CVMetalTextureCacheFlush(g.tex_cache, 0); CFRelease(g.tex_cache); g.tex_cache = nullptr; }
	if (g.transfer) { VTPixelTransferSessionInvalidate(g.transfer); CFRelease(g.transfer); g.transfer = nullptr; }
	if (g.in_pool) { CVPixelBufferPoolRelease(g.in_pool); g.in_pool = nullptr; }
	if (g.out_pool) { CVPixelBufferPoolRelease(g.out_pool); g.out_pool = nullptr; }
	if (g.nv12_pool) { CVPixelBufferPoolRelease(g.nv12_pool); g.nv12_pool = nullptr; }
	g.width = g.height = g.out_w = g.out_h = 0;
	g.avg_ms = 0.0;
	g.frames = 0;
	g.recent_n = g.recent_i = 0;
	g.slow_windows = 0;
	g_p95_ms = 0.0;
	g_active = 0;
	g_last_ms = 0.0;
	g_out_w = 0;
	g_out_h = 0;
}

CVPixelBufferPoolRef MakePool(int w, int h, OSType format)
{
	NSDictionary *attrs = @{
		(id)kCVPixelBufferWidthKey: @(w),
		(id)kCVPixelBufferHeightKey: @(h),
		(id)kCVPixelBufferPixelFormatTypeKey: @(format),
		(id)kCVPixelBufferIOSurfacePropertiesKey: @{},
		(id)kCVPixelBufferMetalCompatibilityKey: @YES,
	};
	CVPixelBufferPoolRef pool = nullptr;
	if (CVPixelBufferPoolCreate(kCFAllocatorDefault, nullptr, (CFDictionaryRef)attrs, &pool) != kCVReturnSuccess)
		return nullptr;
	return pool;
}

bool Setup(int w, int h, int ow, int oh)
{
	Teardown();
	g.device = MTLCreateSystemDefaultDevice();
	if (!g.device || ![MTLFXSpatialScalerDescriptor supportsDevice:g.device])
		return false;
	g.queue = [g.device newCommandQueue];
	if (!g.queue)
		return false;

	g.out_w = ow;
	g.out_h = oh;
	MTLFXSpatialScalerDescriptor *d = [[MTLFXSpatialScalerDescriptor alloc] init];
	d.inputWidth = (NSUInteger)w;
	d.inputHeight = (NSUInteger)h;
	d.outputWidth = (NSUInteger)g.out_w;
	d.outputHeight = (NSUInteger)g.out_h;
	d.colorTextureFormat = MTLPixelFormatBGRA8Unorm;
	d.outputTextureFormat = MTLPixelFormatBGRA8Unorm;
	d.colorProcessingMode = MTLFXSpatialScalerColorProcessingModePerceptual; // gamma-encoded video
	g.scaler = [d newSpatialScalerWithDevice:g.device];
	[d release];
	if (!g.scaler) {
		NSLog(@"[e11] MetalFX: could not create the spatial scaler for %dx%d", w, h);
		return false;
	}
	g.scaler.inputContentWidth = (NSUInteger)w;
	g.scaler.inputContentHeight = (NSUInteger)h;

	if (CVMetalTextureCacheCreate(kCFAllocatorDefault, nullptr, g.device, nullptr, &g.tex_cache) != kCVReturnSuccess)
		return false;
	if (VTPixelTransferSessionCreate(kCFAllocatorDefault, &g.transfer) != noErr)
		return false;
	// RGB -> YUV back to the stream's HD matrix (BT.709); otherwise colours can shift
	VTSessionSetProperty(g.transfer, kVTPixelTransferPropertyKey_DestinationYCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2);
	g.in_pool = MakePool(w, h, kCVPixelFormatType_32BGRA);
	g.out_pool = MakePool(g.out_w, g.out_h, kCVPixelFormatType_32BGRA);
	g.nv12_pool = MakePool(g.out_w, g.out_h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
	if (!g.in_pool || !g.out_pool || !g.nv12_pool)
		return false;
	g.width = w;
	g.height = h;
	NSLog(@"[e11] MetalFX: spatial upscaling %dx%d -> %dx%d on %@", w, h, g.out_w, g.out_h, g.device.name);
	return true;
}

id<MTLTexture> TextureFor(CVPixelBufferRef pb, MTLTextureUsage usage, CVMetalTextureRef *holder)
{
	NSDictionary *attrs = @{ (id)kCVMetalTextureUsage: @(usage) };
	*holder = nullptr;
	if (CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, g.tex_cache, pb, (CFDictionaryRef)attrs,
			MTLPixelFormatBGRA8Unorm, CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), 0, holder) != kCVReturnSuccess
			|| !*holder)
		return nil;
	return CVMetalTextureGetTexture(*holder);
}

AVFrame *CopyNV12(CVPixelBufferRef pb)
{
	const int w = (int)CVPixelBufferGetWidth(pb);
	const int h = (int)CVPixelBufferGetHeight(pb);
	AVFrame *o = av_frame_alloc();
	if (!o)
		return nullptr;
	o->format = AV_PIX_FMT_NV12;
	o->width = w;
	o->height = h;
	if (av_frame_get_buffer(o, 64) < 0) {
		av_frame_free(&o);
		return nullptr;
	}
	CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
	for (int p = 0; p < 2; p++) {
		const uint8_t *src = (const uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pb, p);
		const size_t src_stride = CVPixelBufferGetBytesPerRowOfPlane(pb, p);
		const int rows = std::min((int)CVPixelBufferGetHeightOfPlane(pb, p), p == 0 ? h : (h + 1) / 2);
		const size_t bytes = p == 0 ? (size_t)w : (size_t)((w + 1) / 2) * 2;
		if (!src) {
			CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
			av_frame_free(&o);
			return nullptr;
		}
		for (int r = 0; r < rows; r++)
			memcpy(o->data[p] + (size_t)r * o->linesize[p], src + (size_t)r * src_stride, bytes);
	}
	CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
	return o;
}

} // namespace

bool MacMetalFXUpscale::Available()
{
	static int cached = -1;
	if (cached >= 0)
		return cached == 1;
	cached = 0;
	@autoreleasepool {
		id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
		if (dev) {
			cached = [MTLFXSpatialScalerDescriptor supportsDevice:dev] ? 1 : 0;
			[dev release];
		}
	}
	return cached == 1;
}

void MacMetalFXUpscale::SetEnabled(bool enabled)
{
	g_enabled = enabled;
	if (enabled)
		g_failed = false;
	else
		g_reset_requested = true;
}

bool MacMetalFXUpscale::Enabled() { return g_enabled; }
bool MacMetalFXUpscale::Active() { return g_active.load() != 0 && !g_failed.load(); }
double MacMetalFXUpscale::LastProcessMs() { return g_last_ms; }
int MacMetalFXUpscale::OutputWidth() { return g_out_w; }
int MacMetalFXUpscale::OutputHeight() { return g_out_h; }

void MacMetalFXUpscale::SetTargetSize(int width, int height)
{
	g_target_w = width;
	g_target_h = height;
}

double MacMetalFXUpscale::P95Ms() { return Active() ? g_p95_ms.load() : 0.0; }

bool MacSystemState::OnBattery()
{
	bool battery = false;
	CFTypeRef info = IOPSCopyPowerSourcesInfo();
	if (info) {
		CFStringRef type = IOPSGetProvidingPowerSourceType(info);
		battery = type && CFStringCompare(type, CFSTR(kIOPMBatteryPowerKey), 0) == kCFCompareEqualTo;
		CFRelease(info);
	}
	return battery;
}

bool MacSystemState::LowPowerMode()
{
	@autoreleasepool {
		NSProcessInfo *pi = [NSProcessInfo processInfo];
		return [pi respondsToSelector:@selector(isLowPowerModeEnabled)] && pi.isLowPowerModeEnabled;
	}
}

int MacSystemState::ThermalLevel()
{
	@autoreleasepool {
		return (int)[NSProcessInfo processInfo].thermalState;
	}
}

void MacMetalFXUpscale::Reset()
{
	g_failed = false;
	g_reset_requested = true;
}

AVFrame *MacMetalFXUpscale::Process(const AVFrame *f)
{
	if (g_reset_requested.exchange(false) || (!g_enabled && g.scaler) || (g_failed && g.scaler))
		Teardown();
	if (!g_enabled || g_failed || !Available())
		return nullptr;
	if (!f || f->format != AV_PIX_FMT_VIDEOTOOLBOX || !f->data[3])
		return nullptr;
	if (f->hw_frames_ctx) {
		const AVHWFramesContext *fc = (const AVHWFramesContext *)f->hw_frames_ctx->data;
		if (fc->sw_format != AV_PIX_FMT_NV12)
			return nullptr; // 8-bit SDR only
	}

	CVPixelBufferRef src = (CVPixelBufferRef)f->data[3];
	const int w = (int)CVPixelBufferGetWidth(src);
	const int h = (int)CVPixelBufferGetHeight(src);
	// already at or above 4K: nothing to gain
	if (w <= 0 || h <= 0 || w > 2560 || h > 1440)
		return nullptr;
	int want_w = 0, want_h = 0;
	if (!OutputSizeFor(w, h, want_w, want_h)) {
		if (g.scaler)
			Teardown();
		return nullptr;
	}

	AVFrame *result = nullptr;
	@autoreleasepool {
		if (!g.scaler || w != g.width || h != g.height || want_w != g.out_w || want_h != g.out_h) {
			if (!Setup(w, h, want_w, want_h)) {
				NSLog(@"[e11] MetalFX: not available for this stream, switching it off");
				Teardown();
				g_failed = true;
				return nullptr;
			}
		}
		const auto t0 = std::chrono::steady_clock::now();

		CVPixelBufferRef in = nullptr, out = nullptr, nv = nullptr;
		CVMetalTextureRef in_holder = nullptr, out_holder = nullptr;
		bool ok = CVPixelBufferPoolCreatePixelBuffer(nullptr, g.in_pool, &in) == kCVReturnSuccess
			&& CVPixelBufferPoolCreatePixelBuffer(nullptr, g.out_pool, &out) == kCVReturnSuccess
			&& CVPixelBufferPoolCreatePixelBuffer(nullptr, g.nv12_pool, &nv) == kCVReturnSuccess
			&& VTPixelTransferSessionTransferImage(g.transfer, src, in) == noErr; // YUV -> RGB
		if (ok) {
			id<MTLTexture> in_tex = TextureFor(in, g.scaler.colorTextureUsage | MTLTextureUsageShaderRead, &in_holder);
			id<MTLTexture> out_tex = TextureFor(out, g.scaler.outputTextureUsage | MTLTextureUsageRenderTarget | MTLTextureUsageShaderWrite, &out_holder);
			id<MTLCommandBuffer> cb = (in_tex && out_tex) ? [g.queue commandBuffer] : nil;
			if (cb) {
				g.scaler.colorTexture = in_tex;
				g.scaler.outputTexture = out_tex;
				[g.scaler encodeToCommandBuffer:cb];
				[cb commit];
				[cb waitUntilCompleted];
				ok = cb.status == MTLCommandBufferStatusCompleted;
				if (!ok)
					NSLog(@"[e11] MetalFX: GPU error: %@", cb.error);
			} else {
				ok = false;
			}
			g.scaler.colorTexture = nil;
			g.scaler.outputTexture = nil;
		}
		if (in_holder) CFRelease(in_holder);
		if (out_holder) CFRelease(out_holder);
		if (ok)
			ok = VTPixelTransferSessionTransferImage(g.transfer, out, nv) == noErr; // RGB -> YUV
		if (ok)
			result = CopyNV12(nv);
		if (in) CVPixelBufferRelease(in);
		if (out) CVPixelBufferRelease(out);
		if (nv) CVPixelBufferRelease(nv);
		if (!result) {
			NSLog(@"[e11] MetalFX: processing failed, switching it off");
			g_failed = true;
			return nullptr;
		}
		av_frame_copy_props(result, f);
		result->color_range = AVCOL_RANGE_MPEG; // the NV12 pool is video range
		result->sample_aspect_ratio = f->sample_aspect_ratio;

		const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
		g_last_ms = ms;
		g_out_w = g.out_w;
		g_out_h = g.out_h;
		g.frames++;
		g.avg_ms = g.frames == 1 ? ms : g.avg_ms * 0.95 + ms * 0.05;
		g.recent[g.recent_i] = ms;
		g.recent_i = (g.recent_i + 1) % 120;
		g.recent_n = std::min(g.recent_n + 1, 120);
		if (g.recent_n >= 60 && g.recent_i % 60 == 0) {
			// every ~1 s: 95th percentile, so short spikes that cause stutter count too
			double tmp[120];
			std::copy(g.recent, g.recent + g.recent_n, tmp);
			const int k = (int)(g.recent_n * 0.95);
			std::nth_element(tmp, tmp + k, tmp + g.recent_n);
			g_p95_ms = tmp[k];
			g.slow_windows = tmp[k] > 11.0 ? g.slow_windows + 1 : 0;
		}
		if (g.frames > 180 && (g.avg_ms > 9.0 || g.slow_windows >= 3)) {
			NSLog(@"[e11] MetalFX: too slow on this Mac (avg %.1f ms, p95 %.1f ms), switching it off for this stream",
				g.avg_ms, g_p95_ms.load());
			g_failed = true;
		}
		g_active = 1;
	}
	return result;
}
