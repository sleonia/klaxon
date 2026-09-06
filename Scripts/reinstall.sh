#!/bin/bash
# Reinstall: quit the running app, remove installed copies, then rebuild and
# install a fresh Klaxon.app and relaunch it. Saved preferences and the
# Calendar permission grant are PRESERVED (build-app.sh reuses the stable
# signature) — use clean.sh instead for a full wipe.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Klaxon"

# Build and sign BEFORE touching the installed copy. build-app.sh aborts on a
# signing failure, and the old order removed first — so a failed build left no
# app installed and no process running, which is worse than not rebuilding.
KLAXON_NO_INSTALL=1 ./Scripts/build-app.sh

echo "Quitting ${APP_NAME}…"
pkill -x "$APP_NAME" 2>/dev/null || true

echo "Removing installed copies…"
rm -rf "/Applications/${APP_NAME}.app" "${HOME}/Applications/${APP_NAME}.app"

# Install where launchers index apps — same location rule as build-app.sh.
if [ -w /Applications ]; then
    DEST="/Applications"
else
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi
ditto "build/${APP_NAME}.app" "$DEST/${APP_NAME}.app"
echo "Installed: $DEST/${APP_NAME}.app"

echo "Launching ${APP_NAME}…"
open "$DEST/${APP_NAME}.app"
