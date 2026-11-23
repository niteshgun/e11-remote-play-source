// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// e11: pull an already-paired controller over to this Mac (the DualSense switches slots
// when its paired Mac connects to it). No Bluetooth scanning.
#ifndef E11_MAC_CONTROLLER_SWITCH_H
#define E11_MAC_CONTROLLER_SWITCH_H

#include <QString>

namespace MacControllerSwitch {
	// Returns a short status message for the UI.
	QString ConnectToMac();
	void OpenBluetoothSettings();
}

#endif
