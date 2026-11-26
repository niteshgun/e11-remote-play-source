// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// e11: change the Mac screen's resolution from inside e11 (same list as System Settings >
// Displays with "Show all resolutions"). Changes are made for e11 only: macOS puts the screen
// back when the stream ends, when e11 quits, or if it crashes.
#ifndef E11_MAC_DISPLAY_MODE_H
#define E11_MAC_DISPLAY_MODE_H

#include <QString>
#include <QVariantList>

namespace MacDisplayMode {
	// Resolutions of the screen that `native_view` (a QWindow::winId()) is on, largest first.
	// Each entry: { key, label, width, height, pixelWidth, pixelHeight, current }.
	QVariantList Modes(void *native_view);
	// Switch that screen to the mode with this key (from Modes). True on success.
	bool Set(void *native_view, const QString &key);
	// Put every screen back to its System Settings resolution.
	void Restore();
	// True while e11 has changed a screen's resolution.
	bool Changed();
}

#endif
