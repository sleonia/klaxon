import AppKit
import SwiftUI

/// Lazily creates and reuses the single settings window.
@MainActor
public final class SettingsWindowController {

    private let prefs: Preferences
    private let calendarService: CalendarService
    private let onTestAlert: () -> Void
    private var window: NSWindow?

    public init(prefs: Preferences, calendarService: CalendarService,
                onTestAlert: @escaping () -> Void) {
        self.prefs = prefs
        self.calendarService = calendarService
        self.onTestAlert = onTestAlert
    }

    public func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(prefs: prefs, calendarService: calendarService,
                                       onTestAlert: onTestAlert))
            let window = NSWindow(contentViewController: hosting)
            window.title = "\(AppInfo.name) Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
