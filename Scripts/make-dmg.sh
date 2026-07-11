#!/bin/bash
# Build Klaxon.app (release, ad-hoc signed) and package it into a distributable
# .dmg with a drag-to-Applications layout, and print its SHA-256 (for the
# Homebrew cask). Uses only the built-in hdiutil — no create-dmg dependency.
#
# IMPORTANT: without the paid Apple Developer Program the app is ad-hoc signed
# but NOT notarized, so macOS Gatekeeper warns on first launch of a DOWNLOADED
# copy. Users open it once via right-click → Open (or:
#   xattr -dr com.apple.quarantine /Applications/Klaxon.app
# ). There is no way around this without notarization.
#
# Override the version with VERSION=1.2.0 ./Scripts/make-dmg.sh (CI passes the tag).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Klaxon"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"

# Assemble + ad-hoc sign the bundle without installing it locally.
KLAXON_NO_INSTALL=1 ./Scripts/build-app.sh

APP="build/${APP_NAME}.app"
DMG="build/${APP_NAME}-${VERSION}.dmg"
STAGING="build/dmg-staging"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/${APP_NAME}.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ -format UDZO -ov \
    "$DMG" >/dev/null
rm -rf "$STAGING"

echo "Built:   $DMG"
echo "Size:    $(du -h "$DMG" | cut -f1)"
echo "SHA-256: $(shasum -a 256 "$DMG" | awk '{print $1}')"
