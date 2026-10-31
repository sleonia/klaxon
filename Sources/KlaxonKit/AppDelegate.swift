import AppKit
import EventKit

/// Composition root. Owns every service and drives the
/// fetch → plan → arm → fire → act loop.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    private let prefs = Preferences()
    private let calendar = CalendarService()
    private let scheduler = MeetingScheduler()
    private let overlay = OverlayWindowManager()
    private let hotKey = HotKeyManager()
    private lazy var launchAtLogin = LaunchAtLoginService(prefs: prefs)
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
            launchAtLoginLocation: launchAtLogin.location,
            onSetLaunchAtLogin: { [weak self] on in self?.launchAtLogin.setEnabled(on) },
            onTestAlert: { [weak self] in self?.showTestAlert() })

        wireStatusItem()
        wireOverlay()
        wireObservers()

        hotKey.onToggle = { [weak self] in self?.prefs.paused.toggle() }
        hotKey.register()
        startHousekeeping()

        // Adopt the system's login-item state, don't assert ours over it.
        launchAtLogin.refresh()
        launchAtLogin.logState()

        Task { [weak self] in
            guard let self else { return }
            _ = await self.calendar.requestAccess()
            self.replan()
        }

        // Debug/E2E hook: `Klaxon --test-alert` fires the overlay shortly
        // after launch so the full alert path can be exercised headlessly.
        // `--test-alert 5` shows five meetings due together (4 + 1 skipped).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--test-alert") {
            let count = args.indices.contains(i + 1) ? Int(args[i + 1]) ?? 1 : 1
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                self?.showTestAlert(count: count)
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
        controller.onOpenSettings = { [weak self] in
            // The user may have changed Login Items in System Settings since.
            self?.launchAtLogin.refresh()
            self?.settingsController?.show()
        }
        statusController = controller
    }

    private func wireOverlay() {
        overlay.onJoin = { [weak self] meeting in
            guard let self else { return }
            if let url = meeting.link?.url { NSWorkspace.shared.open(url) }
            // Joining one meeting answers the whole alert: the others on it
            // count as dismissed rather than popping up again.
            self.dismissed.formUnion(self.overlay.currentMeetings.map(\.id))
            self.dismissed.insert(meeting.id)
            self.overlay.dismiss()
            self.replan()
        }
        overlay.onSnooze = { [weak self] meetings, interval in
            guard let self else { return }
            let now = Date()
            for meeting in meetings {
                // The same fire date for all, so they come back as one alert.
                self.snoozes[meeting.id] = interval.map { now.addingTimeInterval($0) }
                    ?? meeting.startDate
                // Allow this occurrence to alert again when the snooze expires.
                self.alerted.remove(meeting.id)
            }
            self.overlay.dismiss()
            self.replan()
        }
        overlay.onDismiss = { [weak self] meetings in
            guard let self else { return }
            self.dismissed.formUnion(meetings.map(\.id))
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

        // Coming back from System Settings › Login Items (where the user may
        // have approved, enabled or removed Klaxon) re-activates the app, so
        // re-read the login item then and the open Settings window stays true.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.launchAtLogin.refresh() }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .prefsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.replan() }
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
    /// ones currently on screen.
    private func plannerExclusions() -> Set<String> {
        dismissed.union(alerted).union(overlay.currentMeetings.map(\.id))
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
        // The fresh group may gain or lose members; it only has to still
        // contain one of the meetings this timer was armed for.
        let armedIDs = Set(plan.meetings.map(\.id))
        guard let fresh, fresh.meetings.contains(where: { armedIDs.contains($0.id) }),
              fresh.fireDate.timeIntervalSinceNow < 2 else {
            replan()
            return
        }

        overlay.show(meetings: fresh.meetings, skippedCount: fresh.skipped.count,
                     background: currentBackground, snoozeMinutes: prefs.snoozeMinutes)
        // Mark shown only if the overlay actually appeared (e.g. a display is
        // attached), so a headless miss retries later rather than vanishing.
        // Skipped meetings (over the per-alert cap) count as shown too, so
        // they don't pop up on their own right after.
        if overlay.isShowing {
            alerted.formUnion((fresh.meetings + fresh.skipped).map(\.id))
        }
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

    /// - Parameter count: sample meetings due together; past the per-alert
    ///   cap the extras are reported as skipped, as a real alert would.
    private func showTestAlert(count: Int = 1) {
        let start = Date().addingTimeInterval(90)
        // A vendor-neutral sample: real alerts show whichever of the 30+
        // supported services Klaxon detects on the actual event.
        let samples = (1...max(count, 1)).map { i in
            Meeting(
                eventIdentifier: "test-alert-\(i)",
                title: count == 1 ? "Sample Meeting (Test)" : "Sample Meeting \(i) (Test)",
                startDate: start,
                endDate: start.addingTimeInterval(1800),
                calendarTitle: "Work",
                calendarColorHex: "#4A90D9",
                link: MeetingLink(
                    serviceName: "Video Call",
                    url: URL(string: "https://example.com/join")!))
        }
        let cap = AlertPlanner.maxMeetingsPerAlert
        overlay.show(meetings: Array(samples.prefix(cap)),
                     skippedCount: max(samples.count - cap, 0),
                     background: currentBackground, snoozeMinutes: prefs.snoozeMinutes)
        SoundPlayer.play(prefs.soundName)
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
