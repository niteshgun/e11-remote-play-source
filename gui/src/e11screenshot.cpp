// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
#include "e11screenshot.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QStandardPaths>
#include <algorithm>
#include <cstdint>
#include <thread>

extern "C" {
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixfmt.h>
}

E11Screenshot &E11Screenshot::Instance()
{
	static E11Screenshot instance;
	return instance;
}

QString E11Screenshot::Folder()
{
	QString pictures = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
	if (pictures.isEmpty())
		pictures = QDir::homePath();
	return pictures + QStringLiteral("/e11 Screenshots");
}

void E11Screenshot::Request()
{
	pending.store(true);
}

static inline uint8_t clamp8(float v)
{
	return (uint8_t)std::min(255.0f, std::max(0.0f, v + 0.5f));
}

// Full-resolution YUV -> RGB for the formats the decoders hand us: NV12 / YUV420P (8-bit)
// and P010 (10-bit, e.g. HDR streams; values are read from the high byte).
static bool ToImage(const AVFrame *f, QImage &img)
{
	const int fmt = f->format;
	const bool nv12 = fmt == AV_PIX_FMT_NV12;
	const bool p010 = fmt == AV_PIX_FMT_P010LE;
	const bool yuv420 = fmt == AV_PIX_FMT_YUV420P || fmt == AV_PIX_FMT_YUVJ420P;
	if ((!nv12 && !p010 && !yuv420) || f->width <= 0 || f->height <= 0 || !f->data[0] || !f->data[1])
		return false;
	if (yuv420 && !f->data[2])
		return false;

	const bool full_range = f->color_range == AVCOL_RANGE_JPEG || fmt == AV_PIX_FMT_YUVJ420P;
	const bool bt2020 = f->colorspace == AVCOL_SPC_BT2020_NCL || f->colorspace == AVCOL_SPC_BT2020_CL;
	// R = Y + rv*V ; G = Y - gu*U - gv*V ; B = Y + bu*U
	const float rv = bt2020 ? 1.4746f : 1.5748f;
	const float gu = bt2020 ? 0.16455f : 0.1873f;
	const float gv = bt2020 ? 0.57135f : 0.4681f;
	const float bu = bt2020 ? 1.8814f : 1.8556f;

	img = QImage(f->width, f->height, QImage::Format_RGB888);
	if (img.isNull())
		return false;

	for (int y = 0; y < f->height; y++) {
		uint8_t *out = img.scanLine(y);
		const int cy = y / 2;
		for (int x = 0; x < f->width; x++) {
			const int cx = x / 2;
			float Y, U, V;
			if (p010) {
				const uint16_t *yr = reinterpret_cast<const uint16_t *>(f->data[0] + (size_t)y * f->linesize[0]);
				const uint16_t *uv = reinterpret_cast<const uint16_t *>(f->data[1] + (size_t)cy * f->linesize[1]);
				Y = (float)(yr[x] >> 8);
				U = (float)(uv[cx * 2] >> 8);
				V = (float)(uv[cx * 2 + 1] >> 8);
			} else if (nv12) {
				Y = f->data[0][(size_t)y * f->linesize[0] + x];
				const uint8_t *uv = f->data[1] + (size_t)cy * f->linesize[1] + (size_t)cx * 2;
				U = uv[0];
				V = uv[1];
			} else {
				Y = f->data[0][(size_t)y * f->linesize[0] + x];
				U = f->data[1][(size_t)cy * f->linesize[1] + cx];
				V = f->data[2][(size_t)cy * f->linesize[2] + cx];
			}
			if (!full_range) {
				Y = (Y - 16.0f) * (255.0f / 219.0f);
				U = (U - 128.0f) * (255.0f / 224.0f);
				V = (V - 128.0f) * (255.0f / 224.0f);
			} else {
				U -= 128.0f;
				V -= 128.0f;
			}
			out[x * 3 + 0] = clamp8(Y + rv * V);
			out[x * 3 + 1] = clamp8(Y - gu * U - gv * V);
			out[x * 3 + 2] = clamp8(Y + bu * U);
		}
	}
	return true;
}

void E11Screenshot::Offer(const AVFrame *frame)
{
	if (!frame || !pending.load(std::memory_order_relaxed))
		return;
	if (!pending.exchange(false))
		return;

	AVFrame *copy = av_frame_alloc();
	if (!copy) {
		emit failed(tr("Out of memory"));
		return;
	}
	int r;
	if (frame->hw_frames_ctx) {
		// GPU frame (zero-copy presentation): one transfer to system memory, only for this shot.
		r = av_hwframe_transfer_data(copy, frame, 0);
		if (r >= 0)
			av_frame_copy_props(copy, frame);
	} else {
		r = av_frame_ref(copy, frame);
	}
	if (r < 0) {
		av_frame_free(&copy);
		emit failed(tr("Couldn't read the picture"));
		return;
	}

	std::thread([this, copy]() mutable {
		QImage img;
		const bool ok = ToImage(copy, img);
		av_frame_free(&copy);
		if (!ok) {
			emit failed(tr("This picture format isn't supported"));
			return;
		}
		const QString folder = Folder();
		QDir().mkpath(folder);
		const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH.mm.ss"));
		QString path = folder + QStringLiteral("/e11 ") + stamp + QStringLiteral(".png");
		for (int n = 2; QFileInfo::exists(path); n++)
			path = folder + QStringLiteral("/e11 ") + stamp + QStringLiteral(" (%1).png").arg(n);
		if (img.save(path, "PNG"))
			emit saved(path);
		else
			emit failed(tr("Couldn't save to %1").arg(folder));
	}).detach();
}
