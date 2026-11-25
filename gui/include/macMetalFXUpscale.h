// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// e11: MetalFX upscaling - Apple's MetalFX spatial scaler (GPU, macOS 13+) on the stream.
// The spatial scaler needs only the frame itself (no motion vectors or depth), so it is the
// MetalFX tool that works on video. Lighter than the Neural Engine upscaler.
#ifndef E11_MAC_METALFX_UPSCALE_H
#define E11_MAC_METALFX_UPSCALE_H

struct AVFrame;

namespace MacMetalFXUpscale {
	// Is MetalFX spatial scaling supported on this Mac?
	bool Available();
	// User switch (quick menu). Safe to call from any thread.
	void SetEnabled(bool enabled);
	bool Enabled();
	// True while frames are actually being upscaled.
	bool Active();
	// Last per-frame processing time in milliseconds (0 if inactive).
	double LastProcessMs();
	// Output size of the last upscaled frame (0 if none).
	int OutputWidth();
	int OutputHeight();
	// Takes an AV_PIX_FMT_VIDEOTOOLBOX frame (decoder frame, or a GPU frame from Clean picture /
	// Pro Motion) and returns a new 2x software NV12 frame, or nullptr to fall back. Frame thread.
	AVFrame *Process(const AVFrame *vt_frame);
	// Drop the scaler (stream ended, resolution changed).
	void Reset();
}

#endif
