// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// e11: raw mouse deltas for mouse-aim on macOS.
#ifndef E11_MAC_MOUSE_AIM_H
#define E11_MAC_MOUSE_AIM_H

#include <functional>

namespace MacMouseAim {
	// Freeze the cursor in place and deliver raw movement deltas (points) to cb.
	void Start(std::function<void(double dx, double dy)> cb);
	// Give the cursor back.
	void Stop();
}

#endif
