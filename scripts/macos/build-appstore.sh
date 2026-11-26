#!/usr/bin/env bash
# e11: build, sign and package e11 Remote Play for the Mac App Store.
#
# You need (one time):
#   - Apple Developer Program membership
#   - In Xcode > Settings > Accounts, or developer.apple.com, these certificates in your keychain:
#       "Apple Distribution: <Your Name> (<TEAMID>)"
#       "3rd Party Mac Developer Installer: <Your Name> (<TEAMID>)"
#   - A Mac App Store provisioning profile for the bundle ID com.e11.remoteplay,
#     downloaded from developer.apple.com > Profiles
#
# Usage:
#   TEAM_ID=ABCDE12345 \
#   PROFILE=~/Downloads/e11_Remote_Play_App_Store.provisionprofile \
#   BUILD_NUMBER=1 \
#   scripts/macos/build-appstore.sh
#
# Optional: APP_IDENTITY / INSTALLER_IDENTITY (full certificate names, if you have more than one),
#           MOLTENVK_DIR (folder holding libMoltenVK.dylib + MoltenVK_icd.json, for the Vulkan renderer).
#
# Output: dist-appstore/e11remoteplay.pkg, ready for the Transporter app.
set -euo pipefail

: "${TEAM_ID:?Set TEAM_ID to your 10-character Apple team ID}"
: "${PROFILE:?Set PROFILE to your Mac App Store .provisionprofile}"
: "${BUILD_NUMBER:?Set BUILD_NUMBER (must go up by one for every upload)}"
BUNDLE_ID="com.e11.remoteplay"
APP_IDENTITY="${APP_IDENTITY:-Apple Distribution: }"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-3rd Party Mac Developer Installer: }"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BREW="$(brew --prefix)"
BUILD="$ROOT/build-appstore"
OUT="$ROOT/dist-appstore"
APP="$OUT/e11remoteplay.app"
cd "$ROOT"

# AGPLv3: the app must point to its public source code.
if grep -q "YOUR-GITHUB-USERNAME" gui/src/qml/SettingsDialog.qml; then
	echo "ERROR: set your public repo URL (sourceUrl) in gui/src/qml/SettingsDialog.qml first." >&2
	exit 1
fi

echo "==> Configure (App Store: no Qt WebEngine, no Steam shortcut)"
cmake -S . -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release \
	-DE11_APPSTORE=ON \
	-DCHIAKI_ENABLE_CLI=OFF -DCHIAKI_ENABLE_TESTS=OFF \
	-DCHIAKI_ENABLE_STEAMDECK_NATIVE=OFF -DCHIAKI_ENABLE_STEAM_SHORTCUT=OFF \
	-DOPENSSL_ROOT_DIR="$BREW/opt/openssl@3" \
	-DCMAKE_PREFIX_PATH="$ROOT/../deps;$BREW/opt/openssl@3;$BREW/opt/qt@6;$BREW/opt/protobuf@29"

echo "==> Build"
CPATH="$BREW/opt/ffmpeg/include" cmake --build "$BUILD" --config Release --target chiaki

echo "==> Bundle Qt and libraries"
rm -rf "$OUT"; mkdir -p "$OUT"
cp -a "$BUILD/gui/e11remoteplay.app" "$APP"
# Scan the QML for imports, but without qtwebengine_import.qml so WebEngine is not bundled.
QMLDIR="$(mktemp -d)"
rsync -a --exclude qtwebengine_import.qml "$ROOT/gui/src/qml/" "$QMLDIR/"
"$BREW/opt/qt@6/bin/macdeployqt" "$APP" -qmldir="$QMLDIR" -libpath="$BREW/lib" -appstore-compliant
rm -rf "$QMLDIR"

if [ -n "${MOLTENVK_DIR:-}" ]; then
	mkdir -p "$APP/Contents/Resources/vulkan/icd.d"
	cp "$MOLTENVK_DIR"/libMoltenVK.dylib "$MOLTENVK_DIR"/MoltenVK_icd.json "$APP/Contents/Resources/vulkan/icd.d/"
fi

if find "$APP" -iname "*WebEngine*" | grep -q .; then
	echo "ERROR: Qt WebEngine ended up in the bundle; Apple will reject it:" >&2
	find "$APP" -iname "*WebEngine*" >&2
	exit 1
fi

echo "==> Version and provisioning profile"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

ENT="$OUT/entitlements.plist"
cp "$ROOT/gui/entitlements-appstore.xml" "$ENT"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" "$ENT"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENT"

echo "==> Sign (inside out)"
sign() { codesign --force --timestamp --sign "$APP_IDENTITY" "$@"; }
find "$APP/Contents" -type f \( -name "*.dylib" -o -name "*.so" \) -print0 | while IFS= read -r -d '' f; do sign "$f"; done
find "$APP/Contents/Frameworks" -maxdepth 1 -name "*.framework" -print0 2>/dev/null | while IFS= read -r -d '' f; do sign "$f"; done
sign --entitlements "$ENT" "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"
codesign -d --entitlements - "$APP" | grep -q "com.apple.security.app-sandbox" || { echo "ERROR: sandbox entitlement missing" >&2; exit 1; }

echo "==> Package"
productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$OUT/e11remoteplay.pkg"
echo
echo "Done: $OUT/e11remoteplay.pkg"
echo "Test first:  open \"$APP\"   (sign in to PSN, connect, stream, controller, mic, screenshot)"
echo "Then upload: open the Transporter app, sign in with your Apple ID, drag the .pkg in."
