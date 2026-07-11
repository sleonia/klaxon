#!/bin/bash
# Builds the release binary, assembles the Klaxon.app bundle, code-signs it,
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

# Prefer the stable self-signed identity from setup-signing.sh (so macOS keeps
# the Calendar permission across rebuilds); fall back to ad-hoc otherwise.
SIGN_ID="Klaxon Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID" \
   && codesign --force --sign "$SIGN_ID" "$APP" 2>/dev/null; then
    echo "Signed with '$SIGN_ID' (stable identity)."
else
    codesign --force --sign - "$APP"
    echo "Ad-hoc signed. Tip: run ./Scripts/setup-signing.sh once so rebuilds"
    echo "keep the Calendar permission instead of re-prompting."
fi
echo "Built: $APP"

# Release/DMG builds only need the assembled bundle, not a local install.
if [ "${KLAXON_NO_INSTALL:-0}" = "1" ]; then
    echo "KLAXON_NO_INSTALL=1 — skipping install."
    exit 0
fi

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
