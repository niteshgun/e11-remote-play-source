// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// Compiled without ARC.
#include "macControllerSwitch.h"

#import <AppKit/AppKit.h>
#import <IOBluetooth/IOBluetooth.h>
#import <GameController/GameController.h>

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

bool MacControllerSwitch::BluetoothPowered()
{
	@autoreleasepool {
		IOBluetoothHostController *hc = [IOBluetoothHostController defaultController];
		return hc && hc.powerState == kBluetoothHCIPowerStateON;
	}
}

int MacControllerSwitch::AirDropOn()
{
#ifdef E11_APPSTORE
	// The App Sandbox can't read other apps' settings: report "unknown".
	return -1;
#endif
	CFPreferencesAppSynchronize(CFSTR("com.apple.sharingd"));
	CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("DiscoverableMode"), CFSTR("com.apple.sharingd"));
	int on = 1; // macOS default is "Contacts Only"
	if (v) {
		if (CFGetTypeID(v) == CFStringGetTypeID() && CFStringCompare((CFStringRef)v, CFSTR("Off"), 0) == kCFCompareEqualTo)
			on = 0;
		CFRelease(v);
	}
	return on;
}

int MacControllerSwitch::HandoffOn()
{
#ifdef E11_APPSTORE
	return -1;
#endif
	CFStringRef app = CFSTR("com.apple.coreservices.useractivityd");
	CFPreferencesSynchronize(app, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
	CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("ActivityAdvertisingAllowed"), app, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
	int on = 1; // default: Handoff allowed
	if (v) {
		if (CFGetTypeID(v) == CFBooleanGetTypeID())
			on = CFBooleanGetValue((CFBooleanRef)v) ? 1 : 0;
		else if (CFGetTypeID(v) == CFNumberGetTypeID()) {
			int n = 1;
			CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n);
			on = n ? 1 : 0;
		}
		CFRelease(v);
	}
	return on;
}

void MacControllerSwitch::OpenAirDropHandoffSettings()
{
	NSWorkspace *ws = [NSWorkspace sharedWorkspace];
	if (![ws openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension"]])
		[ws openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.systempreferences.GeneralSettings"]];
}

void MacControllerSwitch::OpenBluetoothSettings()
{
	NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Bluetooth"];
	if (![[NSWorkspace sharedWorkspace] openURL:url])
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preferences.Bluetooth"]];
}

static void E11KeepButtons(GCController *c)
{
	if (!c)
		return;
	if (@available(macOS 11.0, *)) {
		for (GCControllerElement *el in c.physicalInputProfile.allElements)
			el.preferredSystemGestureState = GCSystemGestureStateDisabled;
	}
}

void MacControllerSwitch::KeepButtonsForApp()
{
	dispatch_async(dispatch_get_main_queue(), ^{
		for (GCController *c in [GCController controllers])
			E11KeepButtons(c);
		[[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidConnectNotification
		                                                  object:nil
		                                                   queue:[NSOperationQueue mainQueue]
		                                              usingBlock:^(NSNotification *note) {
			E11KeepButtons((GCController *)note.object);
		}];
	});
}
