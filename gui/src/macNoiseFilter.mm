// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// e11: "Clean picture" via VideoToolbox VTFrameProcessor (VTTemporalNoiseFilter, macOS 26+).
//
// Same approach as macNeuralUpscale.mm: the VTFrameProcessor classes are looked up at runtime
// and messaged dynamically, so the app builds with any SDK and the feature reports unavailable
// on older macOS. Compiled without ARC: alloc/init objects are released explicitly.
//
// Low latency: only previous frames are used as references (nextFrames is empty), so a frame
// is shown as soon as it is decoded. The very first frame after a (re)start has no reference
// yet and is passed through unfiltered.

#include "macNoiseFilter.h"

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>
#include <objc/message.h>
#include <objc/runtime.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <deque>

extern "C" {
#include <libavutil/buffer.h>
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixfmt.h>
}

static std::atomic<bool> g_enabled{false};
static std::atomic<bool> g_failed{false};
static std::atomic<bool> g_reset_requested{false};
static std::atomic<int> g_active{0};
static std::atomic<double> g_last_ms{0.0};
static std::atomic<float> g_strength{0.5f};

namespace {

const int MAX_REFS = 2; // previous frames kept as references (fewer = less work per frame)

struct State {
	id processor = nil;
	int width = 0, height = 0;
	int prev_count = 0;
	CVPixelBufferPoolRef src_pool = nullptr;
	CVPixelBufferPoolRef dst_pool = nullptr;
	CVPixelBufferPoolRef nv12_pool = nullptr;
	VTPixelTransferSessionRef transfer = nullptr;
	std::deque<std::pair<CVPixelBufferRef, int64_t>> refs; // retained source frames + pts
	double avg_ms = 0.0;
	int frames = 0;
	int64_t pts = 0;
	float strength_used = -1.0f;
	bool discontinuity = true;
};

State g;

Class Cls(const char *name)
{
	return NSClassFromString([NSString stringWithUTF8String:name]);
}

void ClearRefs()
{
	for (auto &r : g.refs)
		CVPixelBufferRelease(r.first);
	g.refs.clear();
	g.discontinuity = true;
}

void Teardown()
{
	ClearRefs();
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
	g.width = g.height = 0;
	g.prev_count = 0;
	g.avg_ms = 0.0;
	g.frames = 0;
	g.strength_used = -1.0f;
	g_active = 0;
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
	Class cfg_cls = Cls("VTTemporalNoiseFilterConfiguration");
	Class proc_cls = Cls("VTFrameProcessor");
	if (!cfg_cls || !proc_cls)
		return false;

	SEL init_sel = sel_registerName("initWithFrameWidth:frameHeight:sourcePixelFormat:");
	id cfg = [cfg_cls alloc];
	if (![cfg respondsToSelector:init_sel]) {
		[cfg release];
		NSLog(@"[e11] Clean picture: configuration initializer not found");
		return false;
	}
	cfg = ((id (*)(id, SEL, NSInteger, NSInteger, OSType))objc_msgSend)(cfg, init_sel, (NSInteger)w, (NSInteger)h,
		(OSType)kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
	if (!cfg) {
		NSLog(@"[e11] Clean picture: %dx%d not supported", w, h);
		return false;
	}

	NSInteger prev = 1;
	SEL pc = sel_registerName("previousFrameCount");
	if ([cfg respondsToSelector:pc])
		prev = ((NSInteger (*)(id, SEL))objc_msgSend)(cfg, pc);
	g.prev_count = (int)std::max<NSInteger>(1, std::min<NSInteger>(prev, MAX_REFS));

	NSDictionary *src_attrs = ((NSDictionary *(*)(id, SEL))objc_msgSend)(cfg, sel_registerName("sourcePixelBufferAttributes"));
	NSDictionary *dst_attrs = ((NSDictionary *(*)(id, SEL))objc_msgSend)(cfg, sel_registerName("destinationPixelBufferAttributes"));
	g.width = w;
	g.height = h;
	g.src_pool = MakePool(src_attrs, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
	g.dst_pool = MakePool(dst_attrs, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
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
		NSLog(@"[e11] Clean picture: could not start session: %@", err);
		[proc release];
		Teardown();
		return false;
	}
	g.processor = proc;
	g.discontinuity = true;
	NSLog(@"[e11] Clean picture: temporal noise filter %dx%d, %d previous frame(s)", w, h, g.prev_count);
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

void ReleasePixelBuffer(void *, uint8_t *data)
{
	CVPixelBufferRelease((CVPixelBufferRef)data);
}

// Wrap a CVPixelBuffer as an AV_PIX_FMT_VIDEOTOOLBOX frame (takes over the caller's reference).
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

id MakeParams(id src_frame, NSArray *prev_frames, id dst_frame, float strength, bool discontinuity)
{
	Class cls = Cls("VTTemporalNoiseFilterParameters");
	if (!cls)
		return nil;
	NSArray *next_frames = @[];
	SEL s1 = sel_registerName("initWithSourceFrame:nextFrames:previousFrames:destinationFrame:filterStrength:hasDiscontinuity:");
	SEL s2 = sel_registerName("initWithSourceFrame:nextFrames:previousFrames:destinationFrame:filterStrength:discontinuity:");
	id obj = [cls alloc];
	SEL s = [obj respondsToSelector:s1] ? s1 : ([obj respondsToSelector:s2] ? s2 : nullptr);
	if (!s) {
		[obj release];
		NSLog(@"[e11] Clean picture: parameters initializer not found");
		return nil;
	}
	return ((id (*)(id, SEL, id, id, id, id, float, Boolean))objc_msgSend)(obj, s, src_frame, next_frames, prev_frames,
		dst_frame, strength, (Boolean)(discontinuity ? 1 : 0));
}

} // namespace

bool MacNoiseFilter::Available()
{
	static int cached = -1;
	if (cached >= 0)
		return cached == 1;
	cached = 0;
	if (@available(macOS 26.0, *)) {
		Class c = Cls("VTTemporalNoiseFilterConfiguration");
		if (c && Cls("VTFrameProcessor") && Cls("VTFrameProcessorFrame") && Cls("VTTemporalNoiseFilterParameters")) {
			SEL s = sel_registerName("isSupported");
			if ([c respondsToSelector:s])
				cached = ((BOOL (*)(id, SEL))objc_msgSend)((id)c, s) ? 1 : 0;
		}
	}
	return cached == 1;
}

void MacNoiseFilter::SetEnabled(bool enabled)
{
	g_enabled = enabled;
	if (enabled)
		g_failed = false;
	else
		g_reset_requested = true;
}

bool MacNoiseFilter::Enabled() { return g_enabled; }
void MacNoiseFilter::SetStrength(float s) { g_strength = s < 0.0f ? 0.0f : (s > 1.0f ? 1.0f : s); }
bool MacNoiseFilter::Active() { return g_active.load() != 0 && !g_failed.load(); }
double MacNoiseFilter::LastProcessMs() { return g_last_ms; }

AVFrame *MacNoiseFilter::Download(const AVFrame *f)
{
	if (!f || f->format != AV_PIX_FMT_VIDEOTOOLBOX || !f->data[3])
		return nullptr;
	CVPixelBufferRef pb = (CVPixelBufferRef)f->data[3];
	const OSType fmt = CVPixelBufferGetPixelFormatType(pb);
	if (fmt != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange && fmt != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
		return nullptr;
	AVFrame *o = CopyNV12(pb);
	if (!o)
		return nullptr;
	av_frame_copy_props(o, f);
	o->color_range = fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ? AVCOL_RANGE_JPEG : AVCOL_RANGE_MPEG;
	o->sample_aspect_ratio = f->sample_aspect_ratio;
	return o;
}

void MacNoiseFilter::Reset()
{
	g_failed = false;
	g_reset_requested = true;
}

AVFrame *MacNoiseFilter::Process(const AVFrame *f, bool keep_on_gpu)
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
	int out_range = -1; // set for the NV12 copy: AVCOL_RANGE_JPEG / AVCOL_RANGE_MPEG
	@autoreleasepool {
		if (!g.processor || w != g.width || h != g.height) {
			if (!Setup(w, h)) {
				g_failed = true;
				Teardown();
				return nullptr;
			}
		}
		const float strength = g_strength.load();
		if (strength != g.strength_used) {
			// strength change flushes the processor's history; start clean
			ClearRefs();
			g.strength_used = strength;
		}
		const auto t0 = std::chrono::steady_clock::now();

		// This frame in the processor's source format; it also becomes a reference afterwards.
		CVPixelBufferRef in = nullptr;
		if (CVPixelBufferPoolCreatePixelBuffer(nullptr, g.src_pool, &in) != kCVReturnSuccess
				|| VTPixelTransferSessionTransferImage(g.transfer, src, in) != noErr) {
			if (in) CVPixelBufferRelease(in);
			g_failed = true;
			return nullptr;
		}
		const int64_t pts_value = g.pts++;

		if (g.refs.empty()) {
			// No reference yet: show this frame as is, keep it for the next one.
			g.refs.emplace_back(in, pts_value);
			return nullptr;
		}

		CVPixelBufferRef out = nullptr;
		if (CVPixelBufferPoolCreatePixelBuffer(nullptr, g.dst_pool, &out) != kCVReturnSuccess) {
			CVPixelBufferRelease(in);
			g_failed = true;
			return nullptr;
		}

		Class frame_cls = Cls("VTFrameProcessorFrame");
		SEL frame_init = sel_registerName("initWithBuffer:presentationTimeStamp:");
		const CMTime pts = CMTimeMake(pts_value, 60);
		id in_frame = ((id (*)(id, SEL, CVPixelBufferRef, CMTime))objc_msgSend)([frame_cls alloc], frame_init, in, pts);
		id out_frame = ((id (*)(id, SEL, CVPixelBufferRef, CMTime))objc_msgSend)([frame_cls alloc], frame_init, out, pts);
		NSMutableArray *prev = [NSMutableArray array];
		for (auto &r : g.refs) {
			id rf = ((id (*)(id, SEL, CVPixelBufferRef, CMTime))objc_msgSend)([frame_cls alloc], frame_init, r.first,
				CMTimeMake(r.second, 60));
			if (rf) {
				[prev addObject:rf];
				[rf release];
			}
		}
		id params = (in_frame && out_frame && prev.count) ? MakeParams(in_frame, prev, out_frame, strength, g.discontinuity) : nil;
		NSError *err = nil;
		BOOL ok = params ? ((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(g.processor,
			sel_registerName("processWithParameters:error:"), params, &err) : NO;
		[params release];
		[in_frame release];
		[out_frame release];

		// keep this source frame as the newest reference
		g.refs.emplace_back(in, pts_value);
		while ((int)g.refs.size() > g.prev_count) {
			CVPixelBufferRelease(g.refs.front().first);
			g.refs.pop_front();
		}

		if (!ok) {
			NSLog(@"[e11] Clean picture: processing failed, switching off: %@", err);
			CVPixelBufferRelease(out);
			g_failed = true;
			return nullptr;
		}
		g.discontinuity = false;

		if (keep_on_gpu) {
			result = WrapPixelBuffer(out); // takes over 'out'
		} else {
			CVPixelBufferRef final_pb = out, nv = nullptr;
			const OSType out_fmt = CVPixelBufferGetPixelFormatType(out);
			if (out_fmt != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange && out_fmt != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
				if (!g.nv12_pool)
					g.nv12_pool = MakePool(nil, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
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
			out_range = full_range ? AVCOL_RANGE_JPEG : AVCOL_RANGE_MPEG;
		}
		if (!result) {
			g_failed = true;
			return nullptr;
		}
		av_frame_copy_props(result, f);
		if (out_range >= 0)
			result->color_range = (enum AVColorRange)out_range;
		result->sample_aspect_ratio = f->sample_aspect_ratio;

		const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
		g_last_ms = ms;
		g.frames++;
		g.avg_ms = g.frames == 1 ? ms : g.avg_ms * 0.95 + ms * 0.05;
		// Leave room for decoding, the Neural Engine upscale and presentation inside 16.7 ms.
		if (g.frames > 180 && g.avg_ms > 8.0) {
			NSLog(@"[e11] Clean picture: too slow on this Mac (%.1f ms/frame), switching it off for this stream", g.avg_ms);
			g_failed = true;
		}
		g_active = 1;
	}
	return result;
}
