// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// e11: Neural Engine super-resolution via VideoToolbox VTFrameProcessor
// (VTLowLatencySuperResolutionScaler, macOS 26+).
//
// The VTFrameProcessor classes are looked up at runtime and messaged dynamically, so the app
// builds with any SDK and runs on older macOS (the feature just reports unavailable there).
// File is compiled without ARC: objects from alloc/init are released explicitly.

#include "macNeuralUpscale.h"

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>
#include <objc/message.h>
#include <objc/runtime.h>

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>

extern "C" {
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixfmt.h>
}

static std::atomic<bool> g_enabled{true};
static std::atomic<bool> g_failed{false};        // fell back for this stream (error or too slow)
static std::atomic<bool> g_reset_requested{false};
static std::atomic<int> g_active{0};
static std::atomic<double> g_last_ms{0.0};
static std::atomic<float> g_scale{0.0f};

namespace {

struct State {
	id processor = nil;
	int width = 0, height = 0;
	int out_w = 0, out_h = 0;
	float scale = 0.0f;
	CVPixelBufferPoolRef src_pool = nullptr;
	CVPixelBufferPoolRef dst_pool = nullptr;
	CVPixelBufferPoolRef nv12_pool = nullptr;
	VTPixelTransferSessionRef transfer = nullptr;
	double avg_ms = 0.0;
	int frames = 0;
	int64_t pts = 0;
};

State g;

Class Cls(const char *name)
{
	return NSClassFromString([NSString stringWithUTF8String:name]);
}

void Teardown()
{
	if (g.processor) {
		SEL end = sel_registerName("endSession");
		if ([g.processor respondsToSelector:end])
			((void (*)(id, SEL))objc_msgSend)(g.processor, end);
		[g.processor release];
		g.processor = nil;
	}
	if (g.src_pool) { CVPixelBufferPoolRelease(g.src_pool); g.src_pool = nullptr; }
	if (g.dst_pool) { CVPixelBufferPoolRelease(g.dst_pool); g.dst_pool = nullptr; }
	if (g.nv12_pool) { CVPixelBufferPoolRelease(g.nv12_pool); g.nv12_pool = nullptr; }
	if (g.transfer) {
		VTPixelTransferSessionInvalidate(g.transfer);
		CFRelease(g.transfer);
		g.transfer = nullptr;
	}
	g.width = g.height = g.out_w = g.out_h = 0;
	g.scale = 0.0f;
	g.avg_ms = 0.0;
	g.frames = 0;
	g_active = 0;
	g_scale = 0.0f;
	g_last_ms = 0.0;
}

CVPixelBufferPoolRef MakePool(NSDictionary *attrs, int w, int h, OSType fallback_format)
{
	NSMutableDictionary *d = attrs ? [[attrs mutableCopy] autorelease] : [NSMutableDictionary dictionary];
	d[(id)kCVPixelBufferWidthKey] = @(w);
	d[(id)kCVPixelBufferHeightKey] = @(h);
	id fmt = d[(id)kCVPixelBufferPixelFormatTypeKey];
	if ([fmt isKindOfClass:[NSArray class]])
		d[(id)kCVPixelBufferPixelFormatTypeKey] = [(NSArray *)fmt count] ? [(NSArray *)fmt firstObject] : @(fallback_format);
	else if (!fmt)
		d[(id)kCVPixelBufferPixelFormatTypeKey] = @(fallback_format);
	if (!d[(id)kCVPixelBufferIOSurfacePropertiesKey])
		d[(id)kCVPixelBufferIOSurfacePropertiesKey] = @{};
	CVPixelBufferPoolRef pool = nullptr;
	if (CVPixelBufferPoolCreate(kCFAllocatorDefault, nullptr, (CFDictionaryRef)d, &pool) != kCVReturnSuccess)
		return nullptr;
	return pool;
}

bool Setup(int w, int h)
{
	Teardown();
	Class cfg_cls = Cls("VTLowLatencySuperResolutionScalerConfiguration");
	Class proc_cls = Cls("VTFrameProcessor");
	if (!cfg_cls || !proc_cls)
		return false;

	// Pick the smallest real upscale the processor offers for this size (1080p -> ~Retina).
	float scale = 2.0f;
	SEL sf = sel_registerName("supportedScaleFactorsForFrameWidth:frameHeight:");
	if ([cfg_cls respondsToSelector:sf]) {
		NSArray *factors = ((NSArray *(*)(id, SEL, NSInteger, NSInteger))objc_msgSend)((id)cfg_cls, sf, (NSInteger)w, (NSInteger)h);
		float best = 0.0f;
		for (NSNumber *n in factors) {
			float f = [n floatValue];
			if (f > 1.01f && (best == 0.0f || f < best))
				best = f;
		}
		if (best == 0.0f) {
			NSLog(@"[e11] Neural upscale: no scale factor supported for %dx%d", w, h);
			return false;
		}
		scale = best;
	}

	SEL init_sel = sel_registerName("initWithFrameWidth:frameHeight:scaleFactor:");
	id cfg = [cfg_cls alloc];
	if (![cfg respondsToSelector:init_sel]) {
		[cfg release];
		return false;
	}
	cfg = ((id (*)(id, SEL, NSInteger, NSInteger, float))objc_msgSend)(cfg, init_sel, (NSInteger)w, (NSInteger)h, scale);
	if (!cfg)
		return false;

	g.width = w;
	g.height = h;
	g.scale = scale;
	g.out_w = ((int)lroundf(w * scale)) & ~1;
	g.out_h = ((int)lroundf(h * scale)) & ~1;

	NSDictionary *src_attrs = ((NSDictionary *(*)(id, SEL))objc_msgSend)(cfg, sel_registerName("sourcePixelBufferAttributes"));
	NSDictionary *dst_attrs = ((NSDictionary *(*)(id, SEL))objc_msgSend)(cfg, sel_registerName("destinationPixelBufferAttributes"));
	g.src_pool = MakePool(src_attrs, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
	g.dst_pool = MakePool(dst_attrs, g.out_w, g.out_h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
	if (!g.src_pool || !g.dst_pool || VTPixelTransferSessionCreate(kCFAllocatorDefault, &g.transfer) != noErr) {
		[cfg release];
		Teardown();
		return false;
	}

	id proc = [[proc_cls alloc] init];
	NSError *err = nil;
	BOOL ok = ((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(proc, sel_registerName("startSessionWithConfiguration:error:"), cfg, &err);
	[cfg release];
	if (!ok) {
		NSLog(@"[e11] Neural upscale: could not start session: %@", err);
		[proc release];
		Teardown();
		return false;
	}
	g.processor = proc;
	g_scale = scale;
	NSLog(@"[e11] Neural upscale: Neural Engine super resolution %dx%d -> %dx%d (x%.2f)", w, h, g.out_w, g.out_h, scale);
	return true;
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
		const int rows = (int)CVPixelBufferGetHeightOfPlane(pb, p);
		const size_t bytes = p == 0 ? (size_t)w : (size_t)((w + 1) / 2) * 2;
		if (!src) {
			CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
			av_frame_free(&o);
			return nullptr;
		}
		for (int r = 0; r < rows && r < (p == 0 ? h : (h + 1) / 2); r++)
			memcpy(o->data[p] + (size_t)r * o->linesize[p], src + (size_t)r * src_stride, bytes);
	}
	CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
	return o;
}

} // namespace

bool MacNeuralUpscale::Available()
{
	static int cached = -1;
	if (cached >= 0)
		return cached == 1;
	cached = 0;
	if (@available(macOS 26.0, *)) {
		Class c = Cls("VTLowLatencySuperResolutionScalerConfiguration");
		if (c && Cls("VTFrameProcessor") && Cls("VTFrameProcessorFrame") && Cls("VTLowLatencySuperResolutionScalerParameters")) {
			SEL s = sel_registerName("isSupported");
			if ([c respondsToSelector:s])
				cached = ((BOOL (*)(id, SEL))objc_msgSend)((id)c, s) ? 1 : 0;
		}
	}
	return cached == 1;
}

void MacNeuralUpscale::SetEnabled(bool enabled)
{
	g_enabled = enabled;
	if (enabled)
		g_failed = false;
	else
		g_reset_requested = true;
}

bool MacNeuralUpscale::Enabled() { return g_enabled; }
bool MacNeuralUpscale::Active() { return g_active.load() != 0 && !g_failed.load(); }
double MacNeuralUpscale::LastProcessMs() { return g_last_ms; }
float MacNeuralUpscale::ScaleFactor() { return g_scale; }

void MacNeuralUpscale::Reset()
{
	g_failed = false;
	g_reset_requested = true;
}

AVFrame *MacNeuralUpscale::Process(const AVFrame *f)
{
	if (g_reset_requested.exchange(false) || (!g_enabled && g.processor) || (g_failed && g.processor))
		Teardown();
	if (!g_enabled || g_failed || !Available())
		return nullptr;
	if (!f || f->format != AV_PIX_FMT_VIDEOTOOLBOX || !f->data[3])
		return nullptr;
	// 8-bit SDR only (HDR 10-bit frames take the normal path)
	if (f->hw_frames_ctx) {
		const AVHWFramesContext *fc = (const AVHWFramesContext *)f->hw_frames_ctx->data;
		if (fc->sw_format != AV_PIX_FMT_NV12)
			return nullptr;
	}

	CVPixelBufferRef src = (CVPixelBufferRef)f->data[3];
	const int w = (int)CVPixelBufferGetWidth(src);
	const int h = (int)CVPixelBufferGetHeight(src);

	AVFrame *result = nullptr;
	@autoreleasepool {
		if (!g.processor || w != g.width || h != g.height) {
			if (!Setup(w, h)) {
				g_failed = true;
				Teardown();
				return nullptr;
			}
		}
		const auto t0 = std::chrono::steady_clock::now();

		CVPixelBufferRef in = nullptr, out = nullptr, nv = nullptr;
		if (CVPixelBufferPoolCreatePixelBuffer(nullptr, g.src_pool, &in) != kCVReturnSuccess
				|| CVPixelBufferPoolCreatePixelBuffer(nullptr, g.dst_pool, &out) != kCVReturnSuccess
				|| VTPixelTransferSessionTransferImage(g.transfer, src, in) != noErr) {
			if (in) CVPixelBufferRelease(in);
			if (out) CVPixelBufferRelease(out);
			g_failed = true;
			return nullptr;
		}

		const CMTime pts = CMTimeMake(g.pts++, 60);
		Class frame_cls = Cls("VTFrameProcessorFrame");
		SEL frame_init = sel_registerName("initWithBuffer:presentationTimeStamp:");
		id in_frame = ((id (*)(id, SEL, CVPixelBufferRef, CMTime))objc_msgSend)([frame_cls alloc], frame_init, in, pts);
		id out_frame = ((id (*)(id, SEL, CVPixelBufferRef, CMTime))objc_msgSend)([frame_cls alloc], frame_init, out, pts);
		id params = nil;
		if (in_frame && out_frame)
			params = ((id (*)(id, SEL, id, id))objc_msgSend)([Cls("VTLowLatencySuperResolutionScalerParameters") alloc],
				sel_registerName("initWithSourceFrame:destinationFrame:"), in_frame, out_frame);
		NSError *err = nil;
		BOOL ok = params ? ((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(g.processor,
			sel_registerName("processWithParameters:error:"), params, &err) : NO;
		[params release];
		[in_frame release];
		[out_frame release];
		CVPixelBufferRelease(in);
		if (!ok) {
			NSLog(@"[e11] Neural upscale: processing failed, falling back: %@", err);
			CVPixelBufferRelease(out);
			g_failed = true;
			return nullptr;
		}

		CVPixelBufferRef final_pb = out;
		const OSType out_fmt = CVPixelBufferGetPixelFormatType(out);
		if (out_fmt != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange && out_fmt != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
			if (!g.nv12_pool)
				g.nv12_pool = MakePool(nil, g.out_w, g.out_h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
			if (!g.nv12_pool || CVPixelBufferPoolCreatePixelBuffer(nullptr, g.nv12_pool, &nv) != kCVReturnSuccess
					|| VTPixelTransferSessionTransferImage(g.transfer, out, nv) != noErr) {
				if (nv) CVPixelBufferRelease(nv);
				CVPixelBufferRelease(out);
				g_failed = true;
				return nullptr;
			}
			final_pb = nv;
		}

		result = CopyNV12(final_pb);
		const bool full_range = CVPixelBufferGetPixelFormatType(final_pb) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
		if (nv) CVPixelBufferRelease(nv);
		CVPixelBufferRelease(out);
		if (!result) {
			g_failed = true;
			return nullptr;
		}
		av_frame_copy_props(result, f);
		result->color_range = full_range ? AVCOL_RANGE_JPEG : AVCOL_RANGE_MPEG;
		result->sample_aspect_ratio = f->sample_aspect_ratio;

		const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
		g_last_ms = ms;
		g.frames++;
		g.avg_ms = g.frames == 1 ? ms : g.avg_ms * 0.95 + ms * 0.05;
		// Must fit comfortably inside a 60 fps frame (16.7 ms) or it would add lag/stutter.
		if (g.frames > 180 && g.avg_ms > 12.0) {
			NSLog(@"[e11] Neural upscale: too slow on this Mac (%.1f ms/frame), switching it off for this stream", g.avg_ms);
			g_failed = true;
		}
		g_active = 1;
	}
	return result;
}
