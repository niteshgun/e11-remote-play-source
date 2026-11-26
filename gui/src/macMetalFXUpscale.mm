// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// e11: MetalFX spatial upscaling of the stream (MTLFXSpatialScaler, macOS 13+).
//
// Per frame, all on the GPU in ONE command buffer except the final copy (fast path):
//   decoded NV12 --compute: YUV->RGB--> BGRA (w x h, GPU-only texture) --MetalFX spatial-->
//   BGRA (ow x oh, GPU-only) --compute: RGB->YUV--> NV12 (ow x oh) --copy--> AVFrame.
// If the compute kernels can't be built, the older path is used: VTPixelTransfer for both
// conversions (two extra synchronous conversions per frame, much slower).
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
static std::atomic<int> g_reason{MacMetalFXUpscale::WaitingForFrames};
static std::atomic<int> g_in_w{0}, g_in_h{0};

// e11: remember why this frame was or wasn't upscaled; anything but Upscaling means not active
static void SetReason(int r)
{
	g_reason = r;
	if (r != MacMetalFXUpscale::Upscaling)
		g_active = 0;
}

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
	// e11 fast path: YUV<->RGB on the GPU in the same command buffer as MetalFX
	id<MTLComputePipelineState> pso_to_rgb = nil;
	id<MTLComputePipelineState> pso_to_yuv = nil;
	id<MTLTexture> rgb_in = nil;   // BGRA w x h (private)
	id<MTLTexture> rgb_out = nil;  // BGRA ow x oh (private)
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
	if (g.pso_to_rgb) { [g.pso_to_rgb release]; g.pso_to_rgb = nil; }
	if (g.pso_to_yuv) { [g.pso_to_yuv release]; g.pso_to_yuv = nil; }
	if (g.rgb_in) { [g.rgb_in release]; g.rgb_in = nil; }
	if (g.rgb_out) { [g.rgb_out release]; g.rgb_out = nil; }
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

// BT.709 YUV <-> RGB on the GPU. `full` = full-range YUV (else video range 16-235/240).
static const char *kE11ConvertKernels = R"MSL(
#include <metal_stdlib>
using namespace metal;

kernel void e11_nv12_to_bgra(texture2d<float, access::read> lumaTex [[texture(0)]],
                             texture2d<float, access::read> chromaTex [[texture(1)]],
                             texture2d<float, access::write> rgbTex [[texture(2)]],
                             constant uint &full [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= rgbTex.get_width() || gid.y >= rgbTex.get_height())
        return;
    float y = lumaTex.read(gid).r;
    float2 c = chromaTex.read(gid / 2).rg;
    if (full == 0) {
        y = (y - 16.0 / 255.0) * (255.0 / 219.0);
        c = (c - 128.0 / 255.0) * (255.0 / 224.0);
    } else {
        c = c - 128.0 / 255.0;
    }
    float3 rgb = float3(y + 1.5748 * c.y,
                        y - 0.1873 * c.x - 0.4681 * c.y,
                        y + 1.8556 * c.x);
    rgbTex.write(float4(saturate(rgb), 1.0), gid);
}

// One thread per 2x2 block: four luma samples + one averaged chroma sample (video range out).
kernel void e11_bgra_to_nv12(texture2d<float, access::read> rgbTex [[texture(0)]],
                             texture2d<float, access::write> lumaTex [[texture(1)]],
                             texture2d<float, access::write> chromaTex [[texture(2)]],
                             uint2 gid [[thread_position_in_grid]])
{
    uint2 base = gid * 2;
    uint w = rgbTex.get_width(), h = rgbTex.get_height();
    if (base.x >= w || base.y >= h)
        return;
    float3 sum = float3(0.0);
    for (uint dy = 0; dy < 2; dy++) {
        for (uint dx = 0; dx < 2; dx++) {
            uint2 p = min(base + uint2(dx, dy), uint2(w - 1, h - 1));
            float3 rgb = rgbTex.read(p).rgb;
            sum += rgb;
            float y = dot(rgb, float3(0.2126, 0.7152, 0.0722));
            lumaTex.write(float4(16.0 / 255.0 + y * (219.0 / 255.0), 0.0, 0.0, 1.0), p);
        }
    }
    float3 rgb = sum * 0.25;
    float y = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    float cb = (rgb.b - y) / 1.8556;
    float cr = (rgb.r - y) / 1.5748;
    chromaTex.write(float4(128.0 / 255.0 + cb * (224.0 / 255.0), 128.0 / 255.0 + cr * (224.0 / 255.0), 0.0, 1.0), gid);
}
)MSL";

// Build the conversion kernels and the GPU-only RGB textures. False = use the VTPixelTransfer path.
bool SetupFastPath(int w, int h)
{
	NSError *err = nil;
	id<MTLLibrary> lib = [g.device newLibraryWithSource:[NSString stringWithUTF8String:kE11ConvertKernels] options:nil error:&err];
	if (!lib) {
		NSLog(@"[e11] MetalFX: fast path unavailable (kernels: %@), using the slower conversion", err);
		return false;
	}
	id<MTLFunction> f1 = [lib newFunctionWithName:@"e11_nv12_to_bgra"];
	id<MTLFunction> f2 = [lib newFunctionWithName:@"e11_bgra_to_nv12"];
	if (f1) g.pso_to_rgb = [g.device newComputePipelineStateWithFunction:f1 error:&err];
	if (f2) g.pso_to_yuv = [g.device newComputePipelineStateWithFunction:f2 error:&err];
	[f1 release];
	[f2 release];
	[lib release];
	MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
		width:(NSUInteger)w height:(NSUInteger)h mipmapped:NO];
	td.storageMode = MTLStorageModePrivate;
	td.usage = g.scaler.colorTextureUsage | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
	g.rgb_in = [g.device newTextureWithDescriptor:td];
	MTLTextureDescriptor *to = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
		width:(NSUInteger)g.out_w height:(NSUInteger)g.out_h mipmapped:NO];
	to.storageMode = MTLStorageModePrivate;
	to.usage = g.scaler.outputTextureUsage | MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
	g.rgb_out = [g.device newTextureWithDescriptor:to];
	if (!g.pso_to_rgb || !g.pso_to_yuv || !g.rgb_in || !g.rgb_out) {
		NSLog(@"[e11] MetalFX: fast path unavailable (%@), using the slower conversion", err);
		if (g.pso_to_rgb) { [g.pso_to_rgb release]; g.pso_to_rgb = nil; }
		if (g.pso_to_yuv) { [g.pso_to_yuv release]; g.pso_to_yuv = nil; }
		if (g.rgb_in) { [g.rgb_in release]; g.rgb_in = nil; }
		if (g.rgb_out) { [g.rgb_out release]; g.rgb_out = nil; }
		return false;
	}
	return true;
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
	const bool fast = SetupFastPath(w, h);
	NSLog(@"[e11] MetalFX: spatial upscaling %dx%d -> %dx%d on %@ (%s)", w, h, g.out_w, g.out_h, g.device.name,
		fast ? "fast GPU path" : "VTPixelTransfer path");
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

// One plane of a (bi-planar) CVPixelBuffer as a Metal texture.
id<MTLTexture> PlaneTexture(CVPixelBufferRef pb, size_t plane, MTLPixelFormat fmt, MTLTextureUsage usage, CVMetalTextureRef *holder)
{
	NSDictionary *attrs = @{ (id)kCVMetalTextureUsage: @(usage) };
	*holder = nullptr;
	if (CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, g.tex_cache, pb, (CFDictionaryRef)attrs, fmt,
			CVPixelBufferGetWidthOfPlane(pb, plane), CVPixelBufferGetHeightOfPlane(pb, plane), plane, holder) != kCVReturnSuccess
			|| !*holder)
		return nil;
	return CVMetalTextureGetTexture(*holder);
}

static MTLSize Groups(id<MTLComputePipelineState> pso, NSUInteger w, NSUInteger h, MTLSize *per_group)
{
	const NSUInteger tw = pso.threadExecutionWidth;
	const NSUInteger th = std::max<NSUInteger>(1, pso.maxTotalThreadsPerThreadgroup / tw);
	*per_group = MTLSizeMake(tw, th, 1);
	return MTLSizeMake((w + tw - 1) / tw, (h + th - 1) / th, 1);
}

// Fast path: everything in one command buffer, one wait. Returns the NV12 output buffer or nullptr.
CVPixelBufferRef ProcessFast(CVPixelBufferRef src)
{
	const OSType fmt = CVPixelBufferGetPixelFormatType(src);
	if (fmt != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange && fmt != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
		return nullptr;
	const uint32_t full = fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ? 1 : 0;
	CVPixelBufferRef nv = nullptr;
	if (CVPixelBufferPoolCreatePixelBuffer(nullptr, g.nv12_pool, &nv) != kCVReturnSuccess)
		return nullptr;
	CVMetalTextureRef h[4] = {};
	id<MTLTexture> src_y = PlaneTexture(src, 0, MTLPixelFormatR8Unorm, MTLTextureUsageShaderRead, &h[0]);
	id<MTLTexture> src_c = PlaneTexture(src, 1, MTLPixelFormatRG8Unorm, MTLTextureUsageShaderRead, &h[1]);
	id<MTLTexture> dst_y = PlaneTexture(nv, 0, MTLPixelFormatR8Unorm, MTLTextureUsageShaderWrite, &h[2]);
	id<MTLTexture> dst_c = PlaneTexture(nv, 1, MTLPixelFormatRG8Unorm, MTLTextureUsageShaderWrite, &h[3]);
	bool ok = false;
	id<MTLCommandBuffer> cb = (src_y && src_c && dst_y && dst_c) ? [g.queue commandBuffer] : nil;
	if (cb) {
		MTLSize per = {};
		id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
		[e setComputePipelineState:g.pso_to_rgb];
		[e setTexture:src_y atIndex:0];
		[e setTexture:src_c atIndex:1];
		[e setTexture:g.rgb_in atIndex:2];
		[e setBytes:&full length:sizeof(full) atIndex:0];
		MTLSize groups = Groups(g.pso_to_rgb, g.rgb_in.width, g.rgb_in.height, &per);
		[e dispatchThreadgroups:groups threadsPerThreadgroup:per];
		[e endEncoding];

		g.scaler.colorTexture = g.rgb_in;
		g.scaler.outputTexture = g.rgb_out;
		[g.scaler encodeToCommandBuffer:cb];
		g.scaler.colorTexture = nil;
		g.scaler.outputTexture = nil;

		e = [cb computeCommandEncoder];
		[e setComputePipelineState:g.pso_to_yuv];
		[e setTexture:g.rgb_out atIndex:0];
		[e setTexture:dst_y atIndex:1];
		[e setTexture:dst_c atIndex:2];
		groups = Groups(g.pso_to_yuv, (g.rgb_out.width + 1) / 2, (g.rgb_out.height + 1) / 2, &per);
		[e dispatchThreadgroups:groups threadsPerThreadgroup:per];
		[e endEncoding];

		[cb commit];
		[cb waitUntilCompleted];
		ok = cb.status == MTLCommandBufferStatusCompleted;
		if (!ok)
			NSLog(@"[e11] MetalFX: GPU error: %@", cb.error);
	}
	for (CVMetalTextureRef t : h)
		if (t) CFRelease(t);
	if (!ok) {
		CVPixelBufferRelease(nv);
		return nullptr;
	}
	return nv;
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
int MacMetalFXUpscale::CurrentReason() { return g_reason.load(); }
int MacMetalFXUpscale::InputWidth() { return g_in_w; }
int MacMetalFXUpscale::InputHeight() { return g_in_h; }

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
	g_reason = WaitingForFrames;
	g_in_w = 0;
	g_in_h = 0;
	g_reset_requested = true;
}

AVFrame *MacMetalFXUpscale::Process(const AVFrame *f)
{
	if (g_reset_requested.exchange(false) || (!g_enabled && g.scaler) || (g_failed && g.scaler))
		Teardown();
	if (!Available()) {
		SetReason(NotSupported);
		return nullptr;
	}
	if (!g_enabled) {
		SetReason(SwitchedOff);
		return nullptr;
	}
	if (g_failed) // reason (TooSlow / StartFailed) was set when it switched off
		return nullptr;
	if (!f || f->format != AV_PIX_FMT_VIDEOTOOLBOX || !f->data[3]) {
		SetReason(SoftwareDecoding);
		return nullptr;
	}
	if (f->hw_frames_ctx) {
		const AVHWFramesContext *fc = (const AVHWFramesContext *)f->hw_frames_ctx->data;
		if (fc->sw_format != AV_PIX_FMT_NV12) {
			SetReason(HdrStream);
			return nullptr; // 8-bit SDR only
		}
	}

	CVPixelBufferRef src = (CVPixelBufferRef)f->data[3];
	const int w = (int)CVPixelBufferGetWidth(src);
	const int h = (int)CVPixelBufferGetHeight(src);
	g_in_w = w;
	g_in_h = h;
	// already above 1440p: nothing to gain
	if (w <= 0 || h <= 0 || w > 2560 || h > 1440) {
		SetReason(StreamAlreadyLarge);
		return nullptr;
	}
	int want_w = 0, want_h = 0;
	if (!OutputSizeFor(w, h, want_w, want_h)) {
		if (g.scaler)
			Teardown();
		SetReason(WindowNotBigger);
		return nullptr;
	}

	AVFrame *result = nullptr;
	@autoreleasepool {
		if (!g.scaler || w != g.width || h != g.height || want_w != g.out_w || want_h != g.out_h) {
			if (!Setup(w, h, want_w, want_h)) {
				NSLog(@"[e11] MetalFX: not available for this stream, switching it off");
				Teardown();
				g_failed = true;
				SetReason(StartFailed);
				return nullptr;
			}
		}
		const auto t0 = std::chrono::steady_clock::now();

		if (g.pso_to_rgb) {
			// fast path
			CVPixelBufferRef nvf = ProcessFast(src);
			if (nvf) {
				result = CopyNV12(nvf);
				CVPixelBufferRelease(nvf);
			}
		} else {
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
		} // slow path
		if (!result) {
			NSLog(@"[e11] MetalFX: processing failed, switching it off");
			g_failed = true;
			SetReason(StartFailed);
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
			SetReason(TooSlow);
		} else {
			g_reason = Upscaling;
			g_active = 1;
		}
	}
	return result;
}
