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

    public var onJoin: ((Meeting) -> Void)?
    public var onSnooze: ((Meeting, TimeInterval?) -> Void)?
    public var onDismiss: ((Meeting) -> Void)?

    private var windows: [NSWindow] = []
    public private(set) var currentMeeting: Meeting?
    private var currentBackground: AlertBackground?
    private var currentSnoozeMinutes: [Int] = []

    public var isShowing: Bool { !windows.isEmpty }

    public init() {}

    public func show(meeting: Meeting, background: AlertBackground, snoozeMinutes: [Int]) {
        // With no display attached there is nowhere to show the alert; leave
        // state untouched so the caller can retry when a screen returns.
        guard !NSScreen.screens.isEmpty else { return }

        dismissWindows()
        currentMeeting = meeting
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
                meeting: meeting,
                background: background,
                snoozeMinutes: snoozeMinutes,
                onJoin: { [weak self] in self?.onJoin?($0) },
                onSnooze: { [weak self] in self?.onSnooze?($0, $1) },
                onDismiss: { [weak self] in self?.onDismiss?($0) }
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
        guard let meeting = currentMeeting, let background = currentBackground else { return }
        show(meeting: meeting, background: background, snoozeMinutes: currentSnoozeMinutes)
    }

    public func dismiss() {
        dismissWindows()
        currentMeeting = nil
    }

    private func dismissWindows() {
        for window in windows { window.close() }
        windows = []
    }

    private func activateApp() {
        // `activate(ignoringOtherApps:)` is deprecated under macOS 14's
        // cooperative activation; prefer the argument-less form when present.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
