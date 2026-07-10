#!/bin/bash
# Removes everything Klaxon installs or generates: the running app, the
# installed bundle, local build artifacts, saved preferences, and its
# calendar-permission grant. Safe to run repeatedly (nothing to remove is fine).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Klaxon"
BUNDLE_ID="com.sleonia.Klaxon"

echo "Quitting ${APP_NAME}…"
pkill -x "$APP_NAME" 2>/dev/null || true

echo "Removing installed app…"
rm -rf "/Applications/${APP_NAME}.app" "${HOME}/Applications/${APP_NAME}.app"

echo "Removing build artifacts…"
rm -rf .build build

echo "Removing saved preferences…"
defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -f "${HOME}/Library/Preferences/${BUNDLE_ID}.plist"

echo "Resetting calendar permission…"
tccutil reset Calendar "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "Done."
echo "Note: if you enabled 'Launch at login', macOS clears the orphaned entry"
echo "shortly after the app is removed (System Settings › General › Login Items)."
