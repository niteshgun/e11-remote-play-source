// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// e11 Pro Motion via VideoToolbox VTFrameProcessor (VTLowLatencyFrameInterpolation, macOS 26+).
//
// Same approach as macNeuralUpscale.mm / macNoiseFilter.mm: classes are looked up at runtime and
// messaged dynamically (builds with any SDK, reports unavailable on older macOS). Compiled
// without ARC: alloc/init objects are released explicitly.
//
// Apple: starting a VTLowLatencyFrameInterpolation session loads an ML model and "may take
// longer than a frame time", so the session is started on a background queue and frames pass
// through untouched until it is ready.

#include "macFrameInterp.h"

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>
#include <dispatch/dispatch.h>
#include <objc/message.h>
#include <objc/runtime.h>

#include <atomic>
#include <chrono>

extern "C" {
#include <libavutil/buffer.h>
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixfmt.h>
}

static std::atomic<bool> g_enabled{false};
static std::atomic<bool> g_failed{false};
static std::atomic<bool> g_reset_requested{false};
static std::atomic<bool> g_discontinuity{true};
static std::atomic<int> g_active{0};
static std::atomic<double> g_last_ms{0.0};

namespace {

enum SetupState { NONE = 0, STARTING = 1, READY = 2, FAILED = 3 };

// Everything below is touched by the frame thread only, except while state == STARTING, when the
// background setup block owns it (the frame thread does not touch it until it sees READY).
struct State {
	std::atomic<int> state{NONE};
	id processor = nil;
	int width = 0, height = 0;
	CVPixelBufferPoolRef src_pool = nullptr;
	CVPixelBufferPoolRef dst_pool = nullptr;
	VTPixelTransferSessionRef transfer = nullptr;
	CVPixelBufferRef prev = nullptr; // our own copy of the previous real frame
	int64_t prev_pts = 0;
	int64_t pts = 0;
	double avg_ms = 0.0;
	int frames = 0;
};

State g;

Class Cls(const char *name)
{
	return NSClassFromString([NSString stringWithUTF8String:name]);
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

void Teardown()
{
	// never while the background setup owns the state
	if (g.state.load() == STARTING)
		return;
	if (g.prev) { CVPixelBufferRelease(g.prev); g.prev = nullptr; }
	if (g.processor) {
		SEL end = sel_registerName("endSession");
		if ([g.processor respondsToSelector:end])
			((void (*)(id, SEL))objc_msgSend)(g.processor, end);
		[g.processor release];
		g.processor = nil;
	}
	if (g.src_pool) { CVPixelBufferPoolRelease(g.src_pool); g.src_pool = nullptr; }
	if (g.dst_pool) { CVPixelBufferPoolRelease(g.dst_pool); g.dst_pool = nullptr; }
	if (g.transfer) {
		VTPixelTransferSessionInvalidate(g.transfer);
		CFRelease(g.transfer);
		g.transfer = nullptr;
	}
	g.width = g.height = 0;
	g.avg_ms = 0.0;
	g.frames = 0;
	g.state = NONE;
	g_active = 0;
	g_last_ms = 0.0;
}

// Runs on a background queue.
bool SetupBlocking(int w, int h)
{
	Class cfg_cls = Cls("VTLowLatencyFrameInterpolationConfiguration");
	Class proc_cls = Cls("VTFrameProcessor");
	if (!cfg_cls || !proc_cls)
		return false;
	SEL init_sel = sel_registerName("initWithFrameWidth:frameHeight:numberOfInterpolatedFrames:");
	id cfg = [cfg_cls alloc];
	if (![cfg respondsToSelector:init_sel]) {
		[cfg release];
		NSLog(@"[e11] Pro Motion: configuration initializer not found");
		return false;
	}
	cfg = ((id (*)(id, SEL, NSInteger, NSInteger, NSInteger))objc_msgSend)(cfg, init_sel, (NSInteger)w, (NSInteger)h, (NSInteger)1);
	if (!cfg) {
		NSLog(@"[e11] Pro Motion: %dx%d not supported", w, h);
		return false;
	}
	NSDictionary *src_attrs = ((NSDictionary *(*)(id, SEL))objc_msgSend)(cfg, sel_registerName("sourcePixelBufferAttributes"));
	NSDictionary *dst_attrs = ((NSDictionary *(*)(id, SEL))objc_msgSend)(cfg, sel_registerName("destinationPixelBufferAttributes"));
	g.src_pool = MakePool(src_attrs, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
	g.dst_pool = MakePool(dst_attrs, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
	if (!g.src_pool || !g.dst_pool || VTPixelTransferSessionCreate(kCFAllocatorDefault, &g.transfer) != noErr) {
		[cfg release];
		return false;
	}
	id proc = [[proc_cls alloc] init];
	NSError *err = nil;
	const auto t0 = std::chrono::steady_clock::now();
	BOOL ok = ((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(proc, sel_registerName("startSessionWithConfiguration:error:"), cfg, &err);
	[cfg release];
	if (!ok) {
		NSLog(@"[e11] Pro Motion: could not start session: %@", err);
		[proc release];
		return false;
	}
	g.processor = proc;
	g.width = w;
	g.height = h;
	const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
	NSLog(@"[e11] Pro Motion: frame interpolation ready for %dx%d (model loaded in %.0f ms)", w, h, ms);
	return true;
}

void StartSetup(int w, int h)
{
	g.state = STARTING;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		@autoreleasepool {
			const bool ok = SetupBlocking(w, h);
			if (ok) {
				g.state.store(READY, std::memory_order_release);
			} else {
				// release whatever the failed setup made, then mark failed
				if (g.src_pool) { CVPixelBufferPoolRelease(g.src_pool); g.src_pool = nullptr; }
				if (g.dst_pool) { CVPixelBufferPoolRelease(g.dst_pool); g.dst_pool = nullptr; }
				if (g.transfer) { VTPixelTransferSessionInvalidate(g.transfer); CFRelease(g.transfer); g.transfer = nullptr; }
				g_failed = true;
				g.state.store(FAILED, std::memory_order_release);
			}
		}
	});
}

void ReleasePixelBuffer(void *, uint8_t *data)
{
	CVPixelBufferRelease((CVPixelBufferRef)data);
}

AVFrame *WrapPixelBuffer(CVPixelBufferRef pb)
{
	AVFrame *o = av_frame_alloc();
	if (!o) {
		CVPixelBufferRelease(pb);
		return nullptr;
	}
	o->buf[0] = av_buffer_create((uint8_t *)pb, 1, ReleasePixelBuffer, nullptr, AV_BUFFER_FLAG_READONLY);
	if (!o->buf[0]) {
		CVPixelBufferRelease(pb);
		av_frame_free(&o);
		return nullptr;
	}
	o->format = AV_PIX_FMT_VIDEOTOOLBOX;
	o->width = (int)CVPixelBufferGetWidth(pb);
	o->height = (int)CVPixelBufferGetHeight(pb);
	o->data[3] = (uint8_t *)pb;
	return o;
}

} // namespace

bool MacFrameInterp::Available()
{
	static int cached = -1;
	if (cached >= 0)
		return cached == 1;
	cached = 0;
	if (@available(macOS 26.0, *)) {
		Class c = Cls("VTLowLatencyFrameInterpolationConfiguration");
		if (c && Cls("VTFrameProcessor") && Cls("VTFrameProcessorFrame") && Cls("VTLowLatencyFrameInterpolationParameters")) {
			SEL s = sel_registerName("isSupported");
			if ([c respondsToSelector:s])
				cached = ((BOOL (*)(id, SEL))objc_msgSend)((id)c, s) ? 1 : 0;
		}
	}
	return cached == 1;
}

void MacFrameInterp::SetEnabled(bool enabled)
{
	if (enabled == g_enabled.load())
		return;
	g_enabled = enabled;
	g_failed = false;
	g_discontinuity = true;
	g_reset_requested = true; // start (or drop) the session cleanly on the next frame
}

bool MacFrameInterp::Enabled() { return g_enabled; }
bool MacFrameInterp::Active() { return g_active.load() != 0 && !g_failed.load(); }
bool MacFrameInterp::Starting() { return g.state.load() == STARTING; }
double MacFrameInterp::LastProcessMs() { return g_last_ms; }
void MacFrameInterp::Discontinuity() { g_discontinuity = true; }

void MacFrameInterp::Reset()
{
	g_failed = false;
	g_reset_requested = true;
}

AVFrame *MacFrameInterp::Interpolate(const AVFrame *f)
{
	if (g_reset_requested.load() && g.state.load() != STARTING) {
		g_reset_requested = false;
		Teardown();
	}
	if (g_failed && g.state.load() == READY)
		Teardown();
	if (!g_enabled || g_failed || !Available())
		return nullptr;
	if (!f || f->format != AV_PIX_FMT_VIDEOTOOLBOX || !f->data[3])
		return nullptr;
	// 8-bit SDR only
	if (f->hw_frames_ctx) {
		const AVHWFramesContext *fc = (const AVHWFramesContext *)f->hw_frames_ctx->data;
		if (fc->sw_format != AV_PIX_FMT_NV12)
			return nullptr;
	}

	CVPixelBufferRef src = (CVPixelBufferRef)f->data[3];
	const int w = (int)CVPixelBufferGetWidth(src);
	const int h = (int)CVPixelBufferGetHeight(src);

	const int st = g.state.load(std::memory_order_acquire);
	if (st == STARTING)
		return nullptr;
	if (st == READY && (w != g.width || h != g.height))
		Teardown();
	if (g.state.load() == NONE) {
		StartSetup(w, h);
		return nullptr;
	}
	if (g.state.load(std::memory_order_acquire) != READY)
		return nullptr;

	AVFrame *result = nullptr;
	@autoreleasepool {
		const auto t0 = std::chrono::steady_clock::now();

		// our own copy of this real frame (never hold the decoder's buffer)
		CVPixelBufferRef cur = nullptr;
		if (CVPixelBufferPoolCreatePixelBuffer(nullptr, g.src_pool, &cur) != kCVReturnSuccess
				|| VTPixelTransferSessionTransferImage(g.transfer, src, cur) != noErr) {
			if (cur) CVPixelBufferRelease(cur);
			g_failed = true;
			return nullptr;
		}
		const int64_t cur_pts = g.pts += 2; // real frames at even ticks, the in-between one at odd

		if (g_discontinuity.exchange(false) || !g.prev) {
			if (g.prev) CVPixelBufferRelease(g.prev);
			g.prev = cur;
			g.prev_pts = cur_pts;
			return nullptr;
		}

		CVPixelBufferRef out = nullptr;
		if (CVPixelBufferPoolCreatePixelBuffer(nullptr, g.dst_pool, &out) != kCVReturnSuccess) {
			CVPixelBufferRelease(cur);
			g_failed = true;
			return nullptr;
		}

		Class frame_cls = Cls("VTFrameProcessorFrame");
		SEL frame_init = sel_registerName("initWithBuffer:presentationTimeStamp:");
		id src_frame = ((id (*)(id, SEL, CVPixelBufferRef, CMTime))objc_msgSend)([frame_cls alloc], frame_init, cur, CMTimeMake(cur_pts, 120));
		id prev_frame = ((id (*)(id, SEL, CVPixelBufferRef, CMTime))objc_msgSend)([frame_cls alloc], frame_init, g.prev, CMTimeMake(g.prev_pts, 120));
		id dst_frame = ((id (*)(id, SEL, CVPixelBufferRef, CMTime))objc_msgSend)([frame_cls alloc], frame_init, out, CMTimeMake(cur_pts - 1, 120));
		id params = nil;
		if (src_frame && prev_frame && dst_frame) {
			SEL p_init = sel_registerName("initWithSourceFrame:previousFrame:interpolationPhase:destinationFrames:");
			id obj = [Cls("VTLowLatencyFrameInterpolationParameters") alloc];
			if ([obj respondsToSelector:p_init])
				params = ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(obj, p_init, src_frame, prev_frame, @[@0.5f], @[dst_frame]);
			else
				[obj release];
		}
		NSError *err = nil;
		BOOL ok = params ? ((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(g.processor,
			sel_registerName("processWithParameters:error:"), params, &err) : NO;
		[params release];
		[src_frame release];
		[prev_frame release];
		[dst_frame release];

		// this real frame becomes the previous one for the next call
		CVPixelBufferRelease(g.prev);
		g.prev = cur;
		g.prev_pts = cur_pts;

		if (!ok) {
			NSLog(@"[e11] Pro Motion: interpolation failed, switching off: %@", err);
			CVPixelBufferRelease(out);
			g_failed = true;
			return nullptr;
		}
		result = WrapPixelBuffer(out); // takes over 'out'
		if (!result) {
			g_failed = true;
			return nullptr;
		}
		av_frame_copy_props(result, f);
		result->sample_aspect_ratio = f->sample_aspect_ratio;

		const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
		g_last_ms = ms;
		g.frames++;
		g.avg_ms = g.frames == 1 ? ms : g.avg_ms * 0.95 + ms * 0.05;
		// Two frames now share 16.7 ms; the interpolation itself must stay well under one half.
		if (g.frames > 180 && g.avg_ms > 7.0) {
			NSLog(@"[e11] Pro Motion: too slow on this Mac (%.1f ms/frame), switching it off for this stream", g.avg_ms);
			g_failed = true;
		}
		g_active = 1;
	}
	return result;
}
