import AppKit
import SwiftUI

/// Borderless windows can't become key by default; buttons need key status.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Shows the alert on *every* screen so it is genuinely unmissable.
@MainActor
public final class OverlayWindowManager {

    /// The one meeting the user chose to join.
    public var onJoin: ((Meeting) -> Void)?
    /// Snooze and Dismiss act on every meeting on the alert.
    public var onSnooze: (([Meeting], TimeInterval?) -> Void)?
    public var onDismiss: (([Meeting]) -> Void)?

    private var windows: [NSWindow] = []
    /// Meetings on the alert now on screen (empty when nothing is showing).
    public private(set) var currentMeetings: [Meeting] = []
    private var currentSkippedCount = 0
    private var currentBackground: AlertBackground?
    private var currentSnoozeMinutes: [Int] = []

    public var isShowing: Bool { !windows.isEmpty }

    public init() {}

    /// - Parameter skippedCount: meetings due together but left off the
    ///   alert (over the cap); the alert mentions them by count only.
    public func show(
        meetings: [Meeting], skippedCount: Int = 0,
        background: AlertBackground, snoozeMinutes: [Int]
    ) {
        // With no display attached there is nowhere to show the alert; leave
        // state untouched so the caller can retry when a screen returns.
        guard !NSScreen.screens.isEmpty, !meetings.isEmpty else { return }

        dismissWindows()
        currentMeetings = meetings
        currentSkippedCount = skippedCount
        currentBackground = background
        currentSnoozeMinutes = snoozeMinutes

        for screen in NSScreen.screens {
            let window = KeyableWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false)
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.collectionBehavior = [
                .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary,
            ]
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.contentView = NSHostingView(rootView: AlertView(
                meetings: meetings,
                skippedCount: skippedCount,
                background: background,
                snoozeMinutes: snoozeMinutes,
                onJoin: { [weak self] in self?.onJoin?($0) },
                onSnooze: { [weak self] interval in
                    guard let self else { return }
                    self.onSnooze?(self.currentMeetings, interval)
                },
                onDismiss: { [weak self] in
                    guard let self else { return }
                    self.onDismiss?(self.currentMeetings)
                }
            ))
            window.setFrame(screen.frame, display: true)
            windows.append(window)
        }

        activateApp()
        for (i, window) in windows.enumerated() {
            if i == 0 {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
        }
    }

    /// Re-issues windows for the current meeting (display config changed).
    public func refreshScreens() {
        guard !currentMeetings.isEmpty, let background = currentBackground else { return }
        show(meetings: currentMeetings, skippedCount: currentSkippedCount,
             background: background, snoozeMinutes: currentSnoozeMinutes)
    }

    public func dismiss() {
        dismissWindows()
        currentMeetings = []
        currentSkippedCount = 0
    }

    private func dismissWindows() {
        for window in windows { window.close() }
        windows = []
    }

    private func activateApp() {
        // Cooperative `activate()` (macOS 14+) is not guaranteed to steal key
        // focus from whatever app the user is currently in — it can leave
        // this accessory app's window frontmost but not actually key, so
        // ↵/⌘1-3/esc (which require key-window status) can silently no-op
        // even though the overlay is visible. This alert exists to interrupt
        // right now, so force focus with the deprecated but currently
        // functional `ignoringOtherApps` form.
        NSApp.activate(ignoringOtherApps: true)
    }
}
