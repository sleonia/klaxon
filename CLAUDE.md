# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Klaxon is a menu-bar-only macOS app (no Dock icon; `NSApplication.accessory` policy) that throws a full-screen alert onto every display just before calendar meetings start. macOS 14+. It is a Swift Package (SPM), not an Xcode project.

## Commands

```sh
swift build                      # dev build (KlaxonKit + Klaxon)
swift run Klaxon                 # run from CLI — see caveat below
swift test                       # all tests (requires full Xcode, see below)
swift test --filter AlertPlannerTests            # one test case
swift test --filter 'AlertPlannerTests/testName' # one test method (regex over test id)

./Scripts/build-app.sh           # build release, assemble+sign Klaxon.app, install to /Applications
./Scripts/make-dmg.sh            # build+ad-hoc-sign, package build/Klaxon-<version>.dmg + print SHA-256 (VERSION= overrides)
./Scripts/reinstall.sh           # quit → remove → rebuild+install → relaunch (keeps prefs + Calendar grant)
./Scripts/setup-signing.sh       # run ONCE: stable local signing identity so Calendar permission survives rebuilds
./Scripts/clean.sh               # uninstall app, wipe build/prefs, reset the Calendar TCC grant

.build/debug/Klaxon --test-alert                 # fire the overlay ~1.5s after launch (headless E2E)
.build/debug/Klaxon --screenshot docs/screenshots # re-render the README screenshots from the real SwiftUI views
```

**After making code changes, reinstall the app** with `./Scripts/reinstall.sh` so the running menu-bar instance reflects them — the installed bundle is the only build that has calendar access, so a `swift build` alone won't show your change in the real app.

Environment caveats that will bite you:
- **`swift test` needs full Xcode.** With only Command Line Tools it fails with `no such module 'XCTest'`. This is environmental, not a code error.
- **Calendar access requires the signed bundle.** A `swift run` / `.build` binary can *never* be granted EventKit access (no bundle, no usage strings). Use `Scripts/build-app.sh` to exercise anything that reads the calendar. `AppInfo.isRunningFromBundle` gates bundle-only APIs (e.g. `SMAppService` launch-at-login).

## Releasing

Distribution is an **ad-hoc-signed, un-notarized** `.dmg` on GitHub Releases —
there is no paid Apple Developer Program, so notarization is impossible and a
**downloaded** copy hits a one-time Gatekeeper prompt (the README documents the
right-click-Open / `xattr` bypass). Ad-hoc signing needs no certificate, so a CI
release job needs no secrets.

- `./Scripts/make-dmg.sh` (or `VERSION=1.2.0 ./Scripts/make-dmg.sh`; default reads
  `CFBundleShortVersionString` from `Resources/Info.plist`) builds + ad-hoc-signs
  the app and writes `build/Klaxon-<version>.dmg`, printing its SHA-256 (a Homebrew
  cask needs that hash).
- To cut a release: bump the version in `Resources/Info.plist`, then:
  ```sh
  ./Scripts/make-dmg.sh
  gh release create v<version> build/Klaxon-<version>.dmg --title "Klaxon v<version>" --notes "…"
  ```
- The DMG is **never committed to git** — it exists only as a Release asset.
  Humans download `/releases/latest`; a Homebrew cask pins the versioned asset URL
  `…/releases/download/v<version>/Klaxon-<version>.dmg` plus the SHA-256.

## Architecture

Two targets: **`KlaxonKit`** holds all logic and UI; **`Klaxon`** is a ~10-line executable (`main.swift`) that wires `NSApplication` → `AppDelegate`.

**The core loop is `fetch → plan → arm → fire → act`, recomputed from scratch on every state change.** `AppDelegate` is the composition root that owns every service and drives it. `replan()` is called on calendar changes, wake-from-sleep, system-clock jumps, preference changes, snooze/dismiss/join, display-config changes, and a 10-minute housekeeping timer. There is no incremental timer adjustment — always recompute. When adding a new trigger, call `replan()`; don't hand-tune timers.

**Purity boundary is the load-bearing convention.** Side effects live at the edges; the interesting decisions are pure and unit-tested:
- `AlertPlanner.nextAlert(meetings, config, snoozes, dismissed, now)` → the single next `AlertPlan`. No clocks, no EventKit, no timers — `now` is passed in. This is what makes scheduling drift-proof and testable.
- `MeetingLinkParser.detect(url, location, notes)` → `MeetingLink?`. Pure; 30+ services matched by host suffix (+ optional path), with schemeless-domain and generic-URL fallbacks.
- `CalendarService` is the **only** EventKit boundary. Everything downstream operates on plain `Meeting` value types (`Sendable`), never `EKEvent`.
- `MeetingScheduler` is a thin wake-safe `DispatchSourceTimer` wrapper; the fire interval is always derived from a target `Date` at arm time, never carried across sleeps.

Keep new logic in this shape: pure functions of value types, with EventKit/timers/AppKit pushed to the composition root, mirrored by a `*Tests` file.

**Per-occurrence decision state** lives in `AppDelegate`: `snoozes` (occurrence id → fire date), `dismissed`, and `alerted` (fire-once guard, cleared on snooze). These feed `plannerExclusions()` so the planner never re-picks them, and `prune()` drops state for occurrences that leave the 48h fetch window. Invariant: a transient calendar-access blip returns `[]` and must **not** wipe live state — mutations are guarded by `calendar.hasAccess`.

**Fire-time pre-flight:** when the armed timer fires, `AppDelegate.fire(_:)` re-fetches and re-plans *before* showing anything, so a meeting moved/cancelled/superseded while the app slept doesn't fire a stale alert.

**Overlay:** `OverlayWindowManager` renders an `AlertView` on *every* `NSScreen` via borderless `KeyableWindow`s at `.screenSaver` level that join all Spaces. Only the first window becomes key (owns keyboard input); the rest are `orderFrontRegardless`. Buttons and keyboard shortcuts no-op until a 700ms arming delay passes, so a click/keystroke in flight when the overlay appears can't instantly dismiss it.

**Reactive settings spine:** `Preferences` is `UserDefaults`-backed; every mutation persists immediately and posts `.prefsChanged`, which `AppDelegate` observes to `replan()` and re-sync launch-at-login. `StatusItemController` and the SwiftUI settings are dumb view layers fed entirely through closures.

**Concurrency:** Swift 6 tools version with strict concurrency; most types are `@MainActor`. Carbon-hotkey and EventKit C callbacks hop back onto the main actor via `MainActor.assumeIsolated`. The global ⌃⌥P pause hotkey uses Carbon `RegisterEventHotKey` specifically to avoid requiring the Accessibility permission an event tap would need.

**Screenshots stay honest:** `ScreenshotRenderer` (`--screenshot`) renders the real `AlertView` offscreen with `ImageRenderer`, so `docs/screenshots/*.png` always match shipping UI and need no Screen Recording permission. Changing alert UI means regenerating these.
