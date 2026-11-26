// e11: PSN sign-in in a native macOS window (WebKit), so the Mac App Store build needs no
// Qt WebEngine (Chromium). The window shows Sony's own sign-in page; when Sony sends the
// browser to the Remote Play redirect address, we catch it and hand it back, so nothing
// has to be copied or pasted.
#ifndef E11_MACPSNSIGNIN_H
#define E11_MACPSNSIGNIN_H

#include <QUrl>
#include <functional>

namespace MacPsnSignIn
{
	// Opens the sign-in window (or brings it forward if it is already open).
	// onRedirect gets the full redirect URL (with ?code=...). onClosed runs if the user
	// closes the window without finishing. Both run on the main thread.
	void Start(const QUrl &loginUrl, std::function<void(const QUrl &)> onRedirect, std::function<void()> onClosed);
	// Closes the window if it is open (no callbacks).
	void Close();
}

#endif
