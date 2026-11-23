// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// Compiled without ARC.
#include "macControllerSwitch.h"

#import <AppKit/AppKit.h>
#import <IOBluetooth/IOBluetooth.h>

static bool LooksLikeController(IOBluetoothDevice *d)
{
	NSString *n = [d.name lowercaseString] ?: @"";
	for (NSString *k in @[@"dualsense", @"wireless controller", @"dualshock", @"xbox", @"pro controller", @"gamepad", @"controller"])
		if ([n containsString:k])
			return true;
	return d.deviceClassMajor == kBluetoothDeviceClassMajorPeripheral &&
	       ((d.deviceClassMinor & 0x0F) == 0x01 || (d.deviceClassMinor & 0x0F) == 0x02);
}

QString MacControllerSwitch::ConnectToMac()
{
	@autoreleasepool {
		NSArray *paired = [IOBluetoothDevice pairedDevices];
		IOBluetoothDevice *best = nil;
		for (IOBluetoothDevice *d in paired) {
			if (!LooksLikeController(d))
				continue;
			if ([d isConnected])
				return QString("%1 is already connected to this Mac.").arg(QString::fromNSString(d.name ?: @"Controller"));
			if (!best)
				best = d;
		}
		if (!best)
			return QString("No controller paired with this Mac yet. One-time setup: hold Circle + PS for 5 s, then connect it in Bluetooth settings.");
		IOReturn r = [best openConnection];
		NSString *name = best.name ?: @"Controller";
		if (r == kIOReturnSuccess || [best isConnected])
			return QString("✓ %1 switched to this Mac.").arg(QString::fromNSString(name));
		return QString("Couldn't reach %1. Make sure it's on (press PS once), then try again.").arg(QString::fromNSString(name));
	}
}

void MacControllerSwitch::OpenBluetoothSettings()
{
	NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Bluetooth"];
	if (![[NSWorkspace sharedWorkspace] openURL:url])
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preferences.Bluetooth"]];
}
