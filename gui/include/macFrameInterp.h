// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// e11 Pro Motion: 60 -> 120 fps frame generation with Apple's ML low-latency frame interpolation
// (VideoToolbox VTFrameProcessor, VTLowLatencyFrameInterpolation, macOS 26+).
//
// For every real decoded frame N it makes one in-between frame from N-1 and N. The caller shows
// the in-between frame at N's time and N half a frame later, so the stream has twice the frames
// at the cost of about half a frame (~8 ms at 60 fps) of extra delay. Best on 120 Hz displays
// (MacBook Pro ProMotion, 120 Hz monitors); it runs on 60 Hz screens too, for testing.
#ifndef E11_MAC_FRAME_INTERP_H
#define E11_MAC_FRAME_INTERP_H

struct AVFrame;

namespace MacFrameInterp {
	// Is the low-latency frame interpolation processor available on this Mac/OS?
	bool Available();
	// User switch (quick menu). Safe to call from any thread.
	void SetEnabled(bool enabled);
	bool Enabled();
	// True while in-between frames are actually being made.
	bool Active();
	// True while the ML model is still loading (first seconds after switching on).
	bool Starting();
	// Last per-frame processing time in milliseconds (0 if inactive).
	double LastProcessMs();
	// Frame thread: give it every real VideoToolbox-decoded frame, in order. Returns the frame
	// halfway between the previous real frame and this one as an AV_PIX_FMT_VIDEOTOOLBOX frame
	// (no hw_frames_ctx), or nullptr (first frame, still loading, disabled, failed).
	// The decoder's buffer is never kept: frames are copied into the processor's own buffers.
	AVFrame *Interpolate(const AVFrame *vt_frame);
	// Forget the previous frame (seek/recovery/resolution change). Next frame starts fresh.
	void Discontinuity();
	// Drop the session (stream ended).
	void Reset();
}

#endif
