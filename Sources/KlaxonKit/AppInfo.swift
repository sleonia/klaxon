import Foundation

/// Single source of truth for the app's public identity.
public enum AppInfo {
    public static let name = "Klaxon"
    public static let bundleID = "com.sleonia.Klaxon"

    /// True when running from the assembled, signed app bundle (as opposed
    /// to `swift run`), which gates bundle-only APIs like SMAppService.
    public static var isRunningFromBundle: Bool {
        Bundle.main.bundleIdentifier == bundleID
    }
}
