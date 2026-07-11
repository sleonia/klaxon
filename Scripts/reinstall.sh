#!/bin/bash
# Reinstall: quit the running app, remove installed copies, then rebuild and
# install a fresh Klaxon.app and relaunch it. Saved preferences and the
# Calendar permission grant are PRESERVED (build-app.sh reuses the stable
# signature) — use clean.sh instead for a full wipe.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Klaxon"

echo "Quitting ${APP_NAME}…"
pkill -x "$APP_NAME" 2>/dev/null || true

echo "Removing installed copies…"
rm -rf "/Applications/${APP_NAME}.app" "${HOME}/Applications/${APP_NAME}.app"

# Rebuild + install fresh (prefers the stable signing identity when present).
./Scripts/build-app.sh

# Relaunch from wherever build-app.sh installed it (same location rule).
if [ -w /Applications ]; then
    DEST="/Applications"
else
    DEST="$HOME/Applications"
fi
echo "Launching ${APP_NAME}…"
open "$DEST/${APP_NAME}.app"
