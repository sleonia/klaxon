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

# Prefer the stable self-signed identity from setup-signing.sh so macOS keeps
# the Calendar permission across rebuilds; fall back to ad-hoc otherwise.
# TCC pins an ad-hoc app's grant to its CDHash, which changes on every build.
#
# KLAXON_ADHOC=1 forces the ad-hoc path for distribution builds: the local
# identity is a self-signed cert that exists only on this machine, so shipping
# it in the DMG would be strictly worse than ad-hoc for whoever downloads it.
SIGN_ID="Klaxon Local Signing"
SIGN_KEYCHAIN="klaxon-signing.keychain"
SIGN_KEYCHAIN_PASS="klaxon-local"

if [ "${KLAXON_ADHOC:-0}" != "1" ] \
   && security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    # The keychain relocks on every reboot/logout, and find-identity keeps
    # listing the identity while it is locked — so the check above passing does
    # NOT mean we can sign. Unlock first; signing a locked keychain dies with
    # errSecInternalComponent.
    #
    # Only when the identity actually lives in OUR keychain: find-identity
    # searches all of them, so an identity imported into the login keychain
    # would otherwise send us to unlock a keychain that isn't there (exit 50),
    # and set -e would kill a build that was fine.
    if security list-keychains -d user | grep -q "$SIGN_KEYCHAIN"; then
        security unlock-keychain -p "$SIGN_KEYCHAIN_PASS" "$SIGN_KEYCHAIN"
    fi
    # Deliberately no ad-hoc fallback here (set -e takes over on failure): a
    # changed signature silently drops the Calendar grant, and the old fallback
    # buried that under a "run setup-signing.sh" tip aimed at someone who
    # already had. Callers must not destroy a working install before this runs.
    codesign --force --sign "$SIGN_ID" "$APP"
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
