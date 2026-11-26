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
	// Pro Motion) and returns a new software NV12 frame upscaled to fit the target size (max 2x), or nullptr to fall back. Frame thread.
	AVFrame *Process(const AVFrame *vt_frame);
	// Drop the scaler (stream ended, resolution changed).
	void Reset();
	// e11 Enhance: the size (in pixels) the picture is shown at. MetalFX upscales to fit this
	// (keeping the aspect ratio, at most 2x) instead of always 2x, so a 1080p stream on a
	// 2560x1664 MacBook Air becomes 2560x1440, not 3840x2160 (2.25x fewer pixels to process).
	void SetTargetSize(int width, int height);
	// 95th percentile processing time over the last ~2 s (0 if inactive).
	double P95Ms();
	// e11: why MetalFX is or isn't upscaling right now (for the Graphics line).
	enum Reason {
		WaitingForFrames = 0,
		Upscaling,
		NotSupported,
		SwitchedOff,
		SoftwareDecoding,   // frames aren't hardware (VideoToolbox) frames
		HdrStream,          // 10-bit HDR: MetalFX path is 8-bit SDR only
		StreamAlreadyLarge, // stream is above 1440p
		WindowNotBigger,    // window/screen isn't at least 1.1x the stream
		TooSlow,            // switched itself off for this stream
		StartFailed         // MetalFX couldn't start for this stream
	};
	int CurrentReason();
	// Size of the stream going in (0 if none yet).
	int InputWidth();
	int InputHeight();
}

// e11 Enhance: system state used by the Auto policy.
namespace MacSystemState {
	bool OnBattery();      // running on battery power
	bool LowPowerMode();   // macOS Low Power Mode is on
	int ThermalLevel();    // 0 nominal, 1 fair, 2 serious, 3 critical
}

#endif
