import AppKit
import EventKit
import ServiceManagement

/// Composition root. Owns every service and drives the
/// fetch → plan → arm → fire → act loop.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    private let prefs = Preferences()
    private let calendar = CalendarService()
    private let scheduler = MeetingScheduler()
    private let overlay = OverlayWindowManager()
    private let hotKey = HotKeyManager()
    private var statusController: StatusItemController?
    private var settingsController: SettingsWindowController?

    // Planner state
    private var meetings: [Meeting] = []
    private var snoozes: [String: Date] = [:]
    private var dismissed: Set<String> = []
    /// Occurrences whose alert has already been shown, so each fires at most
    /// once (cleared for an occurrence when it is snoozed). Without this, two
    /// meetings due at the same time ping-pong the overlay forever.
    private var alerted: Set<String> = []
    private var currentPlan: AlertPlan?

    private var observers: [NSObjectProtocol] = []
    private var housekeepingTimer: Timer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Dev tool: render README screenshots offscreen, then exit.
        if let i = CommandLine.arguments.firstIndex(of: "--screenshot"),
           i + 1 < CommandLine.arguments.count {
            ScreenshotRenderer.render(to: CommandLine.arguments[i + 1])
            exit(0)
        }

        settingsController = SettingsWindowController(
            prefs: prefs, calendarService: calendar,
            onTestAlert: { [weak self] in self?.showTestAlert() })

        wireStatusItem()
        wireOverlay()
        wireObservers()

        hotKey.onToggle = { [weak self] in self?.prefs.paused.toggle() }
        hotKey.register()
        startHousekeeping()

        // Adopt the system's login-item state, don't assert ours over it.
        adoptLaunchAtLoginState()

        Task { [weak self] in
            guard let self else { return }
            _ = await self.calendar.requestAccess()
            self.replan()
        }

        // Debug/E2E hook: `Klaxon --test-alert` fires the overlay shortly
        // after launch so the full alert path can be exercised headlessly.
        if CommandLine.arguments.contains("--test-alert") {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                self?.showTestAlert()
            }
        }
    }

    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Wiring

    private func wireStatusItem() {
        let controller = StatusItemController()
        controller.nextMeeting = { [weak self] in self?.currentPlan?.meeting }
        controller.upcomingMeetings = { [weak self] in
            guard let self else { return [] }
            let now = Date()
            let config = self.prefs.plannerConfig
            // Show exactly the meetings that are eligible to alert, so the menu
            // matches reality (findings #23): honor calendar/all-day/declined
            // filters and hide events already over.
            return self.meetings.filter { m in
                guard m.endDate > now else { return false }
                if m.isAllDay && !config.includeAllDay { return false }
                if m.isDeclined && !config.includeDeclined { return false }
                if config.disabledCalendarIDs.contains(m.calendarID) { return false }
                return true
            }
        }
        controller.permissionState = { [weak self] in
            switch self?.calendar.authorizationStatus {
            case .fullAccess: .granted
            case .notDetermined: .undetermined
            default: .denied
            }
        }
        controller.isPaused = { [weak self] in self?.prefs.paused ?? false }
        controller.menuBarIconOnly = { [weak self] in self?.prefs.menuBarIconOnly ?? false }
        controller.onTogglePause = { [weak self] in self?.prefs.paused.toggle() }
        controller.onTestAlert = { [weak self] in self?.showTestAlert() }
        controller.onOpenSettings = { [weak self] in self?.settingsController?.show() }
        statusController = controller
    }

    private func wireOverlay() {
        overlay.onJoin = { [weak self] meeting in
            guard let self else { return }
            if let url = meeting.link?.url { NSWorkspace.shared.open(url) }
            self.dismissed.insert(meeting.id)
            self.overlay.dismiss()
            self.replan()
        }
        overlay.onSnooze = { [weak self] meeting, interval in
            guard let self else { return }
            let fireAt = interval.map { Date().addingTimeInterval($0) } ?? meeting.startDate
            self.snoozes[meeting.id] = fireAt
            // Allow this occurrence to alert again when the snooze expires.
            self.alerted.remove(meeting.id)
            self.overlay.dismiss()
            self.replan()
        }
        overlay.onDismiss = { [weak self] meeting in
            guard let self else { return }
            self.dismissed.insert(meeting.id)
            self.overlay.dismiss()
            self.replan()
        }
    }

    private func wireObservers() {
        calendar.onChange = { [weak self] in self?.replan() }

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.replan() }
        })

        // A forward clock jump (manual change or large NTP correction) can
        // move a meeting's fire time into the past; recompute from scratch.
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.replan() }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .prefsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncLaunchAtLogin()
                self?.replan()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.overlay.isShowing else { return }
                self.overlay.refreshScreens()
            }
        })
    }

    /// The overlay background selected in preferences (gradient theme or a
    /// custom image, falling back to a gradient if the image is missing).
    private var currentBackground: AlertBackground {
        AlertBackground.resolve(
            themeID: prefs.themeID, customBackgroundPath: prefs.customBackgroundPath)
    }

    // MARK: - Core loop

    /// Refetch, prune, re-arm. Called on every state change (plan.md §3b).
    private func replan() {
        meetings = calendar.fetchMeetings()
        // Only prune persisted decision-state when we actually have a valid
        // view of the calendar; a transient access blip returns [] and would
        // otherwise wipe live snoozes/dismissals.
        if calendar.hasAccess { prune() }
        if prefs.paused, overlay.isShowing { overlay.dismiss() }
        armTimer()
        statusController?.refresh()
    }

    /// Occurrences excluded from planning: dismissed, already-alerted, and the
    /// one currently on screen.
    private func plannerExclusions() -> Set<String> {
        var excluded = dismissed.union(alerted)
        if let showing = overlay.currentMeeting { excluded.insert(showing.id) }
        return excluded
    }

    /// Arms one timer for the next not-yet-shown alert.
    private func armTimer() {
        currentPlan = AlertPlanner.nextAlert(
            meetings: meetings, config: prefs.plannerConfig,
            snoozes: snoozes, dismissed: plannerExclusions(), now: Date())
        if let plan = currentPlan {
            scheduler.schedule(fireAt: plan.fireDate) { [weak self] in self?.fire(plan) }
        } else {
            scheduler.cancel()
        }
    }

    /// Timer fired: pre-flight against a fresh fetch before showing anything.
    private func fire(_ plan: AlertPlan) {
        meetings = calendar.fetchMeetings()
        if calendar.hasAccess { prune() }
        let fresh = AlertPlanner.nextAlert(
            meetings: meetings, config: prefs.plannerConfig,
            snoozes: snoozes, dismissed: plannerExclusions(), now: Date())

        // The event may have been deleted, moved, or superseded while we slept.
        guard let fresh, fresh.meeting.id == plan.meeting.id,
              fresh.fireDate.timeIntervalSinceNow < 2 else {
            replan()
            return
        }

        overlay.show(meeting: fresh.meeting, background: currentBackground,
                     snoozeMinutes: prefs.snoozeMinutes)
        // Mark shown only if the overlay actually appeared (e.g. a display is
        // attached), so a headless miss retries later rather than vanishing.
        if overlay.isShowing { alerted.insert(fresh.meeting.id) }
        SoundPlayer.play(prefs.soundName)
        armTimer()
        statusController?.refresh()
    }

    /// Drops per-occurrence state for occurrences no longer in the window.
    private func prune() {
        let ids = Set(meetings.map(\.id))
        dismissed.formIntersection(ids)
        alerted.formIntersection(ids)
        snoozes = snoozes.filter { ids.contains($0.key) }
    }

    // MARK: - Extras

    private func showTestAlert() {
        let start = Date().addingTimeInterval(90)
        // A vendor-neutral sample: real alerts show whichever of the 30+
        // supported services Klaxon detects on the actual event.
        let meeting = Meeting(
            eventIdentifier: "test-alert",
            title: "Sample Meeting (Test)",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            calendarTitle: "Work",
            calendarColorHex: "#4A90D9",
            link: MeetingLink(
                serviceName: "Video Call",
                url: URL(string: "https://example.com/join")!))
        overlay.show(meeting: meeting, background: currentBackground,
                     snoozeMinutes: prefs.snoozeMinutes)
        SoundPlayer.play(prefs.soundName)
    }

    /// Startup: copy the system's state into the preference, never the reverse.
    ///
    /// The registration lives in the system's Background Task Management
    /// database and the user can change it there (System Settings › General ›
    /// Login Items) without us hearing about it. At launch that record is the
    /// truth and the preference is only a cache of it, so we read, never write.
    ///
    /// Acting on the preference here would be actively destructive:
    /// `launchAtLogin` defaults to `false`, so a user who enabled Klaxon from
    /// System Settings — or an install that inherited a registration — would
    /// get it silently `unregister()`ed on the very next launch.
    private func adoptLaunchAtLoginState() {
        // SMAppService only works from a real bundle, not `swift run`.
        guard AppInfo.isRunningFromBundle else { return }
        let enabled = SMAppService.mainApp.status == .enabled
        if prefs.launchAtLogin != enabled {
            prefs.launchAtLogin = enabled
        }
    }

    /// The user moved the toggle: act on that intent, then report what actually
    /// stuck. Only ever reached from `.prefsChanged` — see
    /// `adoptLaunchAtLoginState()` for why launch must not run this.
    private func syncLaunchAtLogin() {
        // SMAppService only works from a real bundle, not `swift run`.
        guard AppInfo.isRunningFromBundle else { return }
        let service = SMAppService.mainApp
        do {
            if prefs.launchAtLogin, service.status != .enabled {
                try service.register()
            } else if !prefs.launchAtLogin, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("Klaxon: launch-at-login sync failed: \(error)")
        }
        // Only macOS can clear `.requiresApproval`, so a toggle-on that lands
        // here is a dead end: we would snap the switch back off with nothing
        // said. Send the user where the decision actually lives.
        if prefs.launchAtLogin, service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        // Unconditional, not just in `catch`: `register()` also returns without
        // throwing while the item sits at `.requiresApproval`, which is not "on".
        // The inequality guard is load-bearing — assigning fires `didSet` →
        // `.prefsChanged` → straight back into here, which would never settle.
        let actuallyEnabled = service.status == .enabled
        if prefs.launchAtLogin != actuallyEnabled {
            prefs.launchAtLogin = actuallyEnabled
        }
    }

    /// Periodic safety net: re-plan every 10 minutes so a meeting that crosses
    /// into the fetch window (or a clock drift) is picked up even with no
    /// calendar-change or wake notification to trigger it (findings #6/#21).
    private func startHousekeeping() {
        let timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.replan() }
        }
        timer.tolerance = 60
        housekeepingTimer = timer
    }
}
