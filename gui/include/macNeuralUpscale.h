// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// e11: Neural Engine super-resolution for the stream on macOS 26+, using VideoToolbox's
// VTFrameProcessor low-latency super-resolution scaler (Apple's ML video effect for real-time use).
#ifndef E11_MAC_NEURAL_UPSCALE_H
#define E11_MAC_NEURAL_UPSCALE_H

struct AVFrame;

namespace MacNeuralUpscale {
	// Is the low-latency super-resolution processor available on this Mac/OS?
	bool Available();
	// User switch (quick menu). Safe to call from any thread.
	void SetEnabled(bool enabled);
	bool Enabled();
	// True while frames are actually being upscaled (not disabled, not fallen back).
	bool Active();
	// Last per-frame processing time in milliseconds (0 if inactive).
	double LastProcessMs();
	// Scale factor in use (0 if inactive).
	float ScaleFactor();
	// Takes a VideoToolbox-decoded AVFrame and returns a new software AVFrame upscaled on the
	// Neural Engine, or nullptr to fall back to the normal path. Call on the frame thread only.
	AVFrame *Process(const AVFrame *vt_frame);
	// Drop the session (stream ended, resolution changed). Next Process() starts a new one.
	void Reset();
}

#endif
