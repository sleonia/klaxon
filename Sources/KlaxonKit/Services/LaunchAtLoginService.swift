import AppKit
import os
import ServiceManagement

/// The only `SMAppService` boundary.
///
/// The login item lives in the system's Background Task Management database,
/// and the user can change it there (System Settings › General › Login Items)
/// without us hearing about it. So the system record is the truth and
/// `prefs.launchAtLogin` is only a display cache of it:
/// - `refresh()` copies the system state into the pref and never writes the record.
/// - `setEnabled(_:)` is the user's toggle, the only path that registers or
///   unregisters.
///
/// Nothing here reacts to `.prefsChanged`. If it did, any unrelated setting
/// change (the ⌃⌥P pause, a theme) would act on a possibly stale cache and
/// could unregister a working login item or re-add one the user removed.
@MainActor
final class LaunchAtLoginService {

    private let prefs: Preferences
    // os.Logger with public fields: NSLog text shows up as <private> in the
    // system log, which makes it useless as evidence.
    private let log = Logger(subsystem: AppInfo.bundleID, category: "launch-at-login")

    init(prefs: Preferences) {
        self.prefs = prefs
    }

    /// SMAppService only works from a real bundle, not `swift run`.
    var isAvailable: Bool { AppInfo.isRunningFromBundle }

    var location: LoginItemLocation {
        let path = Bundle.main.bundlePath
        let readOnly = (try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? false
        return LoginItemLocation.classify(bundlePath: path, homeDirectory: NSHomeDirectory(),
                                          isOnReadOnlyVolume: readOnly)
    }

    /// Copies the system's state into the preference, never the reverse.
    ///
    /// Acting on the preference here instead would be destructive:
    /// `launchAtLogin` defaults to `false`, so a user who enabled Klaxon from
    /// System Settings, or an install that inherited a registration, would get
    /// it silently unregistered.
    func refresh() {
        guard isAvailable else { return }
        let enabled = SMAppService.mainApp.status == .enabled
        if prefs.launchAtLogin != enabled {
            prefs.launchAtLogin = enabled
        }
    }

    /// The user moved the toggle: act on that intent, then show what stuck.
    func setEnabled(_ on: Bool) {
        guard isAvailable else { return }
        // The toggle's binding doesn't write the pref, so when nothing ends up
        // changing, SwiftUI isn't told and the switch stays where the click
        // left it. Publishing once makes it re-read the final state.
        defer { prefs.objectWillChange.send() }
        let service = SMAppService.mainApp
        do {
            if on {
                // A copy that won't exist at the next login would leave a
                // login item that silently launches nothing.
                guard location.canRegister else {
                    log.notice("not registering from \(Bundle.main.bundlePath, privacy: .public)")
                    refresh()
                    return
                }
                // Replace any existing record, so it points at this copy even
                // if an older one was moved, replaced or left stale.
                if service.status == .enabled {
                    try? service.unregister()
                }
                try service.register()
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            log.error("change to \(on, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
        // Only macOS can clear `.requiresApproval`, so send the user to the
        // place where they can approve it rather than snapping the switch off
        // with nothing said.
        if on, service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        // `register()` can return without throwing while the item still sits
        // at `.requiresApproval`, which is not "on", so always re-read.
        refresh()
    }

    /// One log line per launch, so a future "didn't start at login" report has
    /// the registration state and bundle path to go on.
    func logState() {
        guard isAvailable else { return }
        log.notice("launch: status=\(Self.describe(SMAppService.mainApp.status), privacy: .public) pref=\(self.prefs.launchAtLogin, privacy: .public) bundle=\(Bundle.main.bundlePath, privacy: .public)")
    }

    private static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: "notRegistered"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }
}
