// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// e11: one-key screenshot of the stream. The next frame that reaches the presenter after
// Request() is copied (GPU frames are transferred once), converted to RGB on a worker thread
// and saved as PNG to Pictures/e11 Screenshots. Works on macOS and Windows.
#ifndef E11_SCREENSHOT_H
#define E11_SCREENSHOT_H

#include <QObject>
#include <QString>
#include <atomic>

struct AVFrame;

class E11Screenshot : public QObject
{
	Q_OBJECT

public:
	static E11Screenshot &Instance();

	// Any thread: take a screenshot of the next frame.
	void Request();
	// Frame thread: called for every frame that is about to be presented. Cheap when no
	// screenshot is pending (one atomic load).
	void Offer(const AVFrame *frame);

	static QString Folder();

signals:
	void saved(const QString &path);
	void failed(const QString &reason);

private:
	E11Screenshot() = default;
	std::atomic<bool> pending{false};
};

#endif
