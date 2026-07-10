# Klaxon

**Unmissable full-screen meeting alerts for macOS.**

Klaxon is a lightweight menu-bar app that throws a full-screen alert onto every
display right before your calendar meetings start — so you actually notice them.
When the meeting has a video link, one click takes you straight into the call.

Built for people who lose track of time: heads-down in deep work, context
switching all day, or just tired of tiny notifications that vanish before you
look up.

## Screenshots

The alert fills the screen so you can't miss it, with a one-click Join and your
chosen snooze buttons. Ten built-in themes (or your own image):

![Klaxon full-screen alert — Classic theme](docs/screenshots/alert-classic.png)

![Klaxon full-screen alert — Ocean theme](docs/screenshots/alert-ocean.png)

## Features

- **Full-screen alerts** on every connected display, above other apps and
  Spaces, at a configurable lead time (at start, 1/2/5/10/15 minutes before).
- **One-click join** — detects meeting links for 30+ services (Zoom, Google
  Meet, Microsoft Teams, Webex, Whereby, Jitsi, and more) from an event's URL,
  location, or notes and shows a Join button for whichever it finds.
- **Configurable snooze** — 0–3 snooze buttons of your choosing (default 1 / 3 /
  5 minutes), plus Dismiss.
- **Themes & custom background** — ten built-in gradient themes, or use your own
  image as the alert background.
- **Sounds** — play any macOS system sound with the alert, or none.
- **Calendar-aware** — works with every account already set up in macOS Calendar
  (iCloud, Google, Microsoft/Exchange, …) via EventKit. Choose which calendars
  count; optionally include all-day or declined events.
- **Pause anywhere** — a global ⌃⌥P hotkey (and a menu-bar toggle) pause and
  resume alerts.
- **Menu-bar native** — no Dock icon; shows the next meeting and a countdown.
- **Launch at login** via `SMAppService`.
- **Robust scheduling** — wake-from-sleep and clock-change aware, with a
  pre-flight re-check so moved or cancelled meetings don't fire stale alerts.

## Install

Requires **macOS 14 (Sonoma) or later** and the Xcode command-line tools
(`xcode-select --install`). Then:

```sh
git clone https://github.com/sleonia/klaxon.git
cd klaxon
./Scripts/build-app.sh
```

That one script builds the app, signs it, and installs `Klaxon.app` into your
Applications folder. Open it, grant Calendar access when prompted, and the horn
appears in your menu bar — you're done.

> The build is ad-hoc signed, so the first time you launch it macOS may ask you
> to confirm. If it's blocked, right-click the app and choose **Open**.

Run the test suite with `swift test`.

### Uninstall

```sh
./Scripts/clean.sh
```

Removes the installed app, local build artifacts, saved preferences, and
Klaxon's calendar-permission grant.

## How it works

The core is deliberately split so the interesting logic is pure and testable:

- `MeetingLinkParser` — turns an event's URL/location/notes into a join link.
- `AlertPlanner` — a pure function of `(meetings, config, snoozes, dismissed,
  now)` that decides the single next alert to fire. No clocks, no EventKit.
- `CalendarService` — the EventKit boundary (permission, fetching, change
  monitoring); everything downstream works on plain `Meeting` values.
- `MeetingScheduler` — a thin, wake-safe `DispatchSourceTimer` wrapper.
- `OverlayWindowManager` + `AlertView` — the per-screen full-screen overlay.
- `AppDelegate` — the composition root wiring the fetch → plan → arm → fire → act
  loop, recomputing from scratch on every calendar change, wake, or clock jump.

## Permissions

Klaxon needs **Full Calendar Access** to know when your meetings start. It uses
that access solely to read event times and meeting links locally — nothing
leaves your machine. It does not require Accessibility access.

## License

[MIT](LICENSE) © 2026 sleonia
