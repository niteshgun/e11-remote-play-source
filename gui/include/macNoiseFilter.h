// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// e11: "Clean picture" - Apple's ML temporal noise filter (VideoToolbox VTFrameProcessor,
// VTTemporalNoiseFilter, macOS 26+) on the stream. Removes streaming blockiness, banding and
// noise using the previous frames only (no future frames, so no added latency).
#ifndef E11_MAC_NOISE_FILTER_H
#define E11_MAC_NOISE_FILTER_H

struct AVFrame;

namespace MacNoiseFilter {
	// Is the temporal noise filter available on this Mac/OS?
	bool Available();
	// User switch (quick menu). Safe to call from any thread.
	void SetEnabled(bool enabled);
	bool Enabled();
	// 0.0 (light) .. 1.0 (strong). Changing it flushes the filter's history.
	void SetStrength(float strength);
	// True while frames are actually being filtered (not disabled, not fallen back).
	bool Active();
	// Last per-frame processing time in milliseconds (0 if inactive).
	double LastProcessMs();
	// Takes a VideoToolbox-decoded AVFrame (format AV_PIX_FMT_VIDEOTOOLBOX) and returns a new
	// filtered frame, or nullptr to fall back to the unfiltered frame. Frame thread only.
	//  keep_on_gpu = true : returns an AV_PIX_FMT_VIDEOTOOLBOX frame (no hw_frames_ctx) for the
	//                       next GPU step (Neural Engine upscale).
	//  keep_on_gpu = false: returns a software NV12 frame ready for presentation.
	AVFrame *Process(const AVFrame *vt_frame, bool keep_on_gpu);
	// For a frame returned with keep_on_gpu=true that the next GPU step did not take: copy it to
	// a software NV12 frame for presentation (nullptr if it can't).
	AVFrame *Download(const AVFrame *gpu_frame);
	// Drop the session and history (stream ended, resolution changed).
	void Reset();
}

#endif
