// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// e11: screen resolution switcher (CoreGraphics display modes, "for this app only").
// Compiled without ARC.
#include "macDisplayMode.h"

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

#include <QMap>
#include <QVariantMap>
#include <algorithm>
#include <vector>

static bool g_changed = false;

static CGDirectDisplayID DisplayFor(void *native_view)
{
	NSView *view = (NSView *)native_view;
	NSScreen *screen = view && view.window ? view.window.screen : [NSScreen mainScreen];
	NSNumber *num = screen ? screen.deviceDescription[@"NSScreenNumber"] : nil;
	return num ? (CGDirectDisplayID)num.unsignedIntValue : CGMainDisplayID();
}

static QString KeyFor(CGDisplayModeRef m)
{
	return QString("%1x%2@%3x%4").arg(CGDisplayModeGetWidth(m)).arg(CGDisplayModeGetHeight(m))
		.arg(CGDisplayModeGetPixelWidth(m)).arg(CGDisplayModeGetPixelHeight(m));
}

// All desktop-usable modes, one per key (highest refresh rate wins). Caller releases the array.
static CFArrayRef CopyModes(CGDirectDisplayID d)
{
	const void *keys[] = { kCGDisplayShowDuplicateLowResolutionModes };
	const void *values[] = { kCFBooleanTrue };
	CFDictionaryRef opts = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 1,
		&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFArrayRef all = CGDisplayCopyAllDisplayModes(d, opts);
	CFRelease(opts);
	return all;
}

static CGDisplayModeRef BestModeFor(CFArrayRef all, const QString &key)
{
	CGDisplayModeRef best = nullptr;
	for (CFIndex i = 0; all && i < CFArrayGetCount(all); i++) {
		CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(all, i);
		if (!CGDisplayModeIsUsableForDesktopGUI(m) || KeyFor(m) != key)
			continue;
		if (!best || CGDisplayModeGetRefreshRate(m) > CGDisplayModeGetRefreshRate(best))
			best = m;
	}
	return best;
}

QVariantList MacDisplayMode::Modes(void *native_view)
{
	QVariantList out;
	@autoreleasepool {
		const CGDirectDisplayID d = DisplayFor(native_view);
		CFArrayRef all = CopyModes(d);
		CGDisplayModeRef cur = CGDisplayCopyDisplayMode(d);
		const QString cur_key = cur ? KeyFor(cur) : QString();
		if (cur)
			CGDisplayModeRelease(cur);
		QMap<QString, bool> seen;
		struct Row { size_t w, h, pw, ph; QString key; };
		std::vector<Row> rows;
		for (CFIndex i = 0; all && i < CFArrayGetCount(all); i++) {
			CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(all, i);
			if (!CGDisplayModeIsUsableForDesktopGUI(m))
				continue;
			const QString key = KeyFor(m);
			if (seen.contains(key))
				continue;
			seen.insert(key, true);
			rows.push_back({ CGDisplayModeGetWidth(m), CGDisplayModeGetHeight(m),
				CGDisplayModeGetPixelWidth(m), CGDisplayModeGetPixelHeight(m), key });
		}
		if (all)
			CFRelease(all);
		// Like System Settings: biggest workspace first; for the same size, sharper (more pixels) first
		std::sort(rows.begin(), rows.end(), [](const Row &a, const Row &b) {
			if (a.w != b.w) return a.w > b.w;
			if (a.h != b.h) return a.h > b.h;
			return a.pw > b.pw;
		});
		// Hide low-resolution duplicates when a sharper (HiDPI) version of the same size exists
		QMap<QString, bool> sizes;
		for (const Row &r : rows) {
			const QString size = QString("%1x%2").arg(r.w).arg(r.h);
			if (sizes.contains(size))
				continue;
			sizes.insert(size, true);
			QVariantMap v;
			v["key"] = r.key;
			v["label"] = QString("%1 × %2").arg(r.w).arg(r.h);
			v["width"] = (int)r.w;
			v["height"] = (int)r.h;
			v["pixelWidth"] = (int)r.pw;
			v["pixelHeight"] = (int)r.ph;
			v["current"] = r.key == cur_key;
			out.append(v);
		}
	}
	return out;
}

bool MacDisplayMode::Set(void *native_view, const QString &key)
{
	bool ok = false;
	@autoreleasepool {
		const CGDirectDisplayID d = DisplayFor(native_view);
		CFArrayRef all = CopyModes(d);
		CGDisplayModeRef m = BestModeFor(all, key);
		CGDisplayConfigRef cfg = nullptr;
		if (m && CGBeginDisplayConfiguration(&cfg) == kCGErrorSuccess) {
			CGConfigureDisplayWithDisplayMode(cfg, d, m, nullptr);
			// kCGConfigureForAppOnly: macOS restores the screen when e11 quits (or crashes)
			ok = CGCompleteDisplayConfiguration(cfg, kCGConfigureForAppOnly) == kCGErrorSuccess;
			if (ok)
				g_changed = true;
			else
				NSLog(@"[e11] Display: couldn't switch to %s", key.toUtf8().constData());
		}
		if (all)
			CFRelease(all);
	}
	return ok;
}

void MacDisplayMode::Restore()
{
	if (!g_changed)
		return;
	CGRestorePermanentDisplayConfiguration();
	g_changed = false;
}

bool MacDisplayMode::Changed() { return g_changed; }

bool MacDisplayMode::AnyScreenHDR()
{
	@autoreleasepool {
		for (NSScreen *s in [NSScreen screens])
			if (s.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0)
				return true;
	}
	return false;
}
