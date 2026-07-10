#!/bin/bash
# Builds the release binary, assembles the ad-hoc-signed Klaxon.app bundle,
# and installs it to an Applications folder so Spotlight/Raycast index it.
#
# TCC (calendar permission) requires a real bundle with usage strings —
# a bare `swift run` binary can never be granted calendar access.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Klaxon"
swift build -c release

APP="build/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp .build/release/Klaxon "$APP/Contents/MacOS/${APP_NAME}"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign - "$APP"
echo "Built: $APP"

# Install where launchers index apps. Prefer /Applications, fall back to
# ~/Applications (no admin needed).
if [ -w /Applications ]; then
    DEST="/Applications"
else
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi
rm -rf "$DEST/${APP_NAME}.app"
ditto "$APP" "$DEST/${APP_NAME}.app"
echo "Installed: $DEST/${APP_NAME}.app"
