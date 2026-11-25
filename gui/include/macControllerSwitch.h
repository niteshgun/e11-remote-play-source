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

	// Smooth-play checks (read-only, no scanning). AirDrop/Handoff: 1 on, 0 off.
	bool BluetoothPowered();
	int AirDropOn();
	int HandoffOn();
	void OpenAirDropHandoffSettings();

	// Keep the PS button (and Create/Options) for e11 and the PS5: stop macOS Game Mode
	// from using it to open its Game Overlay. Applies to controllers now and later.
	void KeepButtonsForApp();
}

#endif
