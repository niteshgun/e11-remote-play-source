// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
#include "aiplayrecorder.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMutexLocker>
#include <QStandardPaths>
#include <algorithm>

extern "C" {
#include <libavutil/frame.h>
#include <libavutil/pixfmt.h>
}

static std::atomic<int> g_e11_frames{0};
void e11CountFrame() { g_e11_frames.fetch_add(1, std::memory_order_relaxed); }
int e11TakeFrameCount() { return g_e11_frames.exchange(0); }

AIPlayRecorder &AIPlayRecorder::Instance()
{
	static AIPlayRecorder instance;
	return instance;
}

QString AIPlayRecorder::RootFolder() const
{
	return QStandardPaths::writableLocation(QStandardPaths::MoviesLocation) + "/e11 AI Play";
}

QString AIPlayRecorder::CurrentFolder() const
{
	QMutexLocker locker(&mutex);
	return folder;
}

double AIPlayRecorder::TotalMinutesOnDisk() const
{
	const qint64 frame_bytes = (qint64)FRAME_W * FRAME_H * 3;
	qint64 frames = 0;
	QDirIterator it(RootFolder(), QStringList() << "frames.u8", QDir::Files, QDirIterator::Subdirectories);
	while (it.hasNext()) {
		it.next();
		frames += it.fileInfo().size() / frame_bytes;
	}
	return frames / (double)RECORD_FPS / 60.0;
}

bool AIPlayRecorder::Start()
{
	QMutexLocker locker(&mutex);
	if (recording)
		return true;
	const QString name = QDateTime::currentDateTime().toString("yyyy-MM-dd_HH-mm-ss");
	folder = RootFolder() + "/" + name;
	if (!QDir().mkpath(folder))
		return false;
	frames_file.setFileName(folder + "/frames.u8");
	inputs_file.setFileName(folder + "/inputs.csv");
	if (!frames_file.open(QIODevice::WriteOnly) || !inputs_file.open(QIODevice::WriteOnly | QIODevice::Text)) {
		frames_file.close();
		inputs_file.close();
		return false;
	}
	inputs_file.write("index,ms,buttons,l2,r2,lx,ly,rx,ry\n");

	QJsonObject meta;
	meta["app"] = "e11 Remote Play";
	meta["frame_width"] = FRAME_W;
	meta["frame_height"] = FRAME_H;
	meta["channels"] = 3;
	meta["pixel_format"] = "rgb24";
	meta["fps"] = RECORD_FPS;
	meta["started"] = QDateTime::currentDateTime().toString(Qt::ISODate);
	QFile meta_file(folder + "/meta.json");
	if (meta_file.open(QIODevice::WriteOnly))
		meta_file.write(QJsonDocument(meta).toJson());

	rgb.assign((size_t)FRAME_W * FRAME_H * 3, 0);
	frames_recorded = 0;
	last_frame_ms = -1000;
	clock.start();
	recording = true;
	return true;
}

void AIPlayRecorder::Stop()
{
	QMutexLocker locker(&mutex);
	if (!recording)
		return;
	recording = false;
	frames_file.close();
	inputs_file.close();
}

void AIPlayRecorder::SetControllerState(const ChiakiControllerState &state)
{
	if (!recording)
		return;
	QMutexLocker locker(&state_mutex);
	last_state = state;
}

static inline uint8_t clamp8(float v)
{
	return (uint8_t)std::clamp(v, 0.0f, 255.0f);
}

bool AIPlayRecorder::Downscale(const AVFrame *f, uint8_t *out) const
{
	const bool nv12 = f->format == AV_PIX_FMT_NV12;
	const bool yuv420 = f->format == AV_PIX_FMT_YUV420P || f->format == AV_PIX_FMT_YUVJ420P;
	if ((!nv12 && !yuv420) || f->width <= 0 || f->height <= 0 || !f->data[0] || !f->data[1])
		return false;
	const bool full_range = f->color_range == AVCOL_RANGE_JPEG || f->format == AV_PIX_FMT_YUVJ420P;
	const float bw = f->width / (float)FRAME_W;
	const float bh = f->height / (float)FRAME_H;
	for (int oy = 0; oy < FRAME_H; oy++) {
		for (int ox = 0; ox < FRAME_W; ox++) {
			// average a 4x4 grid of luma samples inside the block
			float ysum = 0.0f;
			for (int sy = 0; sy < 4; sy++) {
				const int y = std::min(f->height - 1, (int)((oy + (sy + 0.5f) / 4.0f) * bh));
				const uint8_t *row = f->data[0] + (size_t)y * f->linesize[0];
				for (int sx = 0; sx < 4; sx++) {
					const int x = std::min(f->width - 1, (int)((ox + (sx + 0.5f) / 4.0f) * bw));
					ysum += row[x];
				}
			}
			float Y = ysum / 16.0f;
			const int cx = std::min((f->width - 1) / 2, (int)((ox + 0.5f) * bw) / 2);
			const int cy = std::min((f->height - 1) / 2, (int)((oy + 0.5f) * bh) / 2);
			float U, V;
			if (nv12) {
				const uint8_t *uv = f->data[1] + (size_t)cy * f->linesize[1] + (size_t)cx * 2;
				U = uv[0];
				V = uv[1];
			} else {
				U = f->data[1][(size_t)cy * f->linesize[1] + cx];
				V = f->data[2][(size_t)cy * f->linesize[2] + cx];
			}
			// BT.709 YUV -> RGB
			if (!full_range) {
				Y = (Y - 16.0f) * (255.0f / 219.0f);
				U = (U - 128.0f) * (255.0f / 224.0f);
				V = (V - 128.0f) * (255.0f / 224.0f);
			} else {
				U -= 128.0f;
				V -= 128.0f;
			}
			uint8_t *p = out + ((size_t)oy * FRAME_W + ox) * 3;
			p[0] = clamp8(Y + 1.5748f * V);
			p[1] = clamp8(Y - 0.1873f * U - 0.4681f * V);
			p[2] = clamp8(Y + 1.8556f * U);
		}
	}
	return true;
}

void AIPlayRecorder::SubmitFrame(const AVFrame *frame)
{
	if (!recording || !frame)
		return;
	QMutexLocker locker(&mutex);
	if (!recording)
		return;
	const qint64 now = clock.elapsed();
	if (now - last_frame_ms < 1000 / RECORD_FPS)
		return;
	if (!Downscale(frame, rgb.data()))
		return;
	last_frame_ms = now;

	ChiakiControllerState s;
	{
		QMutexLocker state_locker(&state_mutex);
		s = last_state;
	}
	const int index = frames_recorded.load();
	frames_file.write(reinterpret_cast<const char *>(rgb.data()), (qint64)rgb.size());
	inputs_file.write(QString("%1,%2,%3,%4,%5,%6,%7,%8,%9\n")
		.arg(index).arg(now).arg(s.buttons).arg(s.l2_state).arg(s.r2_state)
		.arg(s.left_x).arg(s.left_y).arg(s.right_x).arg(s.right_y).toUtf8());
	frames_recorded = index + 1;
}
