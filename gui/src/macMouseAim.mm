// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
#include "macMouseAim.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static id g_monitor = nil;
static std::function<void(double, double)> g_callback;

void MacMouseAim::Start(std::function<void(double dx, double dy)> cb)
{
	Stop();
	g_callback = std::move(cb);
	NSEventMask mask = NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged
		| NSEventMaskRightMouseDragged | NSEventMaskOtherMouseDragged;
	g_monitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent *(NSEvent *event) {
		if(g_callback)
			g_callback(event.deltaX, event.deltaY);
		return event;
	}];
	// Keep the (hidden) cursor still while we read raw movement,
	// so it can never leave the window or hit a screen edge.
	CGAssociateMouseAndMouseCursorPosition(false);
}

void MacMouseAim::Stop()
{
	if(g_monitor)
	{
		[NSEvent removeMonitor:g_monitor];
		g_monitor = nil;
	}
	g_callback = nullptr;
	CGAssociateMouseAndMouseCursorPosition(true);
}
