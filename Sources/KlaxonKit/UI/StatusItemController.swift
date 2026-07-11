import AppKit

/// Menu bar presence: icon + next-meeting countdown, and the app menu.
/// All data flows in through closures so this stays a dumb view layer.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {

    public enum PermissionState {
        case granted, denied, undetermined
    }

    // MARK: - Wiring (set by AppDelegate)

    public var nextMeeting: (() -> Meeting?)?
    public var upcomingMeetings: (() -> [Meeting])?
    public var permissionState: (() -> PermissionState)?
    public var isPaused: (() -> Bool)?
    public var menuBarIconOnly: (() -> Bool)?
    public var onTogglePause: (() -> Void)?
    public var onTestAlert: (() -> Void)?
    public var onOpenSettings: (() -> Void)?

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var refreshTimer: Timer?

    public override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // Klaxon horn, falling back across OS symbol availability, then to
        // a bell. Template image so it renders monochrome in the menu bar.
        let symbol = ["horn.blast.fill", "horn.fill", "bell.fill"]
            .lazy
            .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: "Klaxon") }
            .first
        symbol?.isTemplate = true
        statusItem.button?.image = symbol
        statusItem.button?.imagePosition = .imageLeading

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 5
        refreshTimer = timer

        refresh()
    }

    // MARK: - Title

    public func refresh() {
        guard let button = statusItem.button else { return }
        button.title = Self.statusTitle(
            paused: isPaused?() == true,
            meeting: nextMeeting?(),
            now: Date(),
            iconOnly: menuBarIconOnly?() == true)
    }

    /// Pure title logic, testable without a live status item. Icon-only hides
    /// the meeting title and countdown; "Paused" still shows since it is app
    /// state the user set, not private meeting data.
    static func statusTitle(paused: Bool, meeting: Meeting?, now: Date, iconOnly: Bool) -> String {
        if paused { return " Paused" }
        if iconOnly { return "" }
        guard let meeting else { return "" }
        let dt = meeting.startDate.timeIntervalSince(now)
        let when = dt < 60 ? "now" : "in \(shortCountdown(dt))"
        return " \(truncate(meeting.title, to: 24)) · \(when)"
    }

    static func shortCountdown(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        return "\(s / 86_400)d"
    }

    static func truncate(_ s: String, to limit: Int) -> String {
        s.count <= limit ? s : String(s.prefix(limit - 1)) + "…"
    }

    // MARK: - Menu

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let state = permissionState?(), state != .granted {
            let warn = NSMenuItem(
                title: "⚠️ Calendar access required…",
                action: #selector(openPrivacySettings), keyEquivalent: "")
            warn.target = self
            warn.isEnabled = true
            menu.addItem(warn)
            menu.addItem(.separator())
        }

        menu.addItem(NSMenuItem.sectionHeader(title: "Upcoming"))
        let upcoming = upcomingMeetings?() ?? []
        if upcoming.isEmpty {
            let none = NSMenuItem(title: "No meetings in the next 48 hours", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for meeting in upcoming.prefix(5) {
                let item = NSMenuItem(
                    title: "\(Self.menuTime(for: meeting.startDate))   \(Self.truncate(meeting.title, to: 40))",
                    action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        let pause = NSMenuItem(
            title: isPaused?() == true ? "Resume Alerts" : "Pause Alerts",
            action: #selector(togglePause), keyEquivalent: "p")
        pause.keyEquivalentModifierMask = [.control, .option]
        pause.target = self
        pause.isEnabled = true
        menu.addItem(pause)

        let test = NSMenuItem(title: "Test Alert", action: #selector(testAlert), keyEquivalent: "")
        test.target = self
        test.isEnabled = true
        menu.addItem(test)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settings.isEnabled = true
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit \(AppInfo.name)",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        quit.isEnabled = true
        menu.addItem(quit)
    }

    static func menuTime(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    // MARK: - Actions

    @objc private func togglePause() { onTogglePause?() }
    @objc private func testAlert() { onTestAlert?() }
    @objc private func openSettings() { onOpenSettings?() }

    @objc private func openPrivacySettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }
}
