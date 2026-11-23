// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// e11 AI Play, phase 1: records what the player sees and does, for imitation learning.
//
// Each recording is a folder:
//   frames.u8    raw RGB frames, FRAME_W x FRAME_H x 3 bytes each, back to back
//   inputs.csv   one line per frame: index, ms since start, buttons, l2, r2, lx, ly, rx, ry
//   meta.json    sizes, rate, start time
// Frames are captured at most RECORD_FPS times a second and downscaled to FRAME_W x FRAME_H.
#ifndef E11_AIPLAY_RECORDER_H
#define E11_AIPLAY_RECORDER_H

#include <chiaki/controller.h>

#include <QElapsedTimer>
#include <QFile>
#include <QMutex>
#include <QString>
#include <atomic>
#include <vector>

struct AVFrame;

class AIPlayRecorder
{
	public:
		static constexpr int FRAME_W = 128;
		static constexpr int FRAME_H = 72;
		static constexpr int RECORD_FPS = 15;

		static AIPlayRecorder &Instance();

		// Starts a new recording folder under ~/Movies/e11 AI Play. Returns false on error.
		bool Start();
		void Stop();
		bool IsRecording() const { return recording.load(); }
		int FramesRecorded() const { return frames_recorded.load(); }
		QString RootFolder() const;
		QString CurrentFolder() const;
		// Total minutes recorded across all sessions on disk (for the menu).
		double TotalMinutesOnDisk() const;

		// Called for every controller state sent to the PS5 (GUI thread).
		void SetControllerState(const ChiakiControllerState &state);
		// Called for every decoded frame about to be shown (frame thread).
		void SubmitFrame(const AVFrame *frame);

	private:
		AIPlayRecorder() = default;
		bool Downscale(const AVFrame *frame, uint8_t *out_rgb) const;

		std::atomic<bool> recording{false};
		std::atomic<int> frames_recorded{0};
		mutable QMutex mutex;      // guards files + folder
		QMutex state_mutex;        // guards last_state
		ChiakiControllerState last_state = {};
		QFile frames_file;
		QFile inputs_file;
		QString folder;
		QElapsedTimer clock;
		qint64 last_frame_ms = -1000;
		std::vector<uint8_t> rgb;
};

#endif
