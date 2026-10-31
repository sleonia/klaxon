import Foundation

/// Where the running copy of the app lives, judged for launch at login.
///
/// macOS records the bundle's path when the app registers itself as a login
/// item, and at login it launches whatever is at that path. Registering from a
/// copy that will vanish (an App Translocation folder, a mounted disk image)
/// leaves a login item that silently does nothing. Pure: the caller supplies
/// the one file-system fact needed (whether the volume is read-only).
public enum LoginItemLocation: Equatable, Sendable {
    /// Inside /Applications, ~/Applications, or an Applications folder at the
    /// root of another writable volume.
    case applications
    /// Outside the Applications folders but stable. Registering works as long as
    /// the app stays there.
    case elsewhere
    /// A path that won't exist at the next login. Never register from here.
    case temporary(Reason)

    public enum Reason: Equatable, Sendable {
        /// macOS ran a quarantined download from a randomized read-only copy.
        case translocated
        /// Running from a read-only mounted volume, such as the release disk image.
        case mountedVolume
    }

    /// - Parameter isOnReadOnlyVolume: whether the bundle's volume is mounted
    ///   read-only. Release disk images are; a second drive usually isn't.
    public static func classify(bundlePath: String, homeDirectory: String,
                                isOnReadOnlyVolume: Bool) -> LoginItemLocation {
        let path = (bundlePath as NSString).standardizingPath
        if path.contains("/AppTranslocation/") { return .temporary(.translocated) }
        let components = (path as NSString).pathComponents   // ["/", "Volumes", name, ...]
        let onOtherVolume = components.count > 2 && components[1] == "Volumes"
        if onOtherVolume && isOnReadOnlyVolume { return .temporary(.mountedVolume) }
        var roots = ["/Applications", (homeDirectory as NSString).appendingPathComponent("Applications")]
        if onOtherVolume { roots.append("/Volumes/\(components[2])/Applications") }
        if roots.contains(where: { path.hasPrefix($0 + "/") }) { return .applications }
        return .elsewhere
    }

    public var canRegister: Bool {
        if case .temporary = self { return false }
        return true
    }

    /// Text for the settings screen, or nil when there is nothing to say.
    public var explanation: String? {
        switch self {
        case .applications:
            return nil
        case .elsewhere:
            return "Klaxon isn't in the Applications folder. Launch at login only works while it stays where it is now."
        case .temporary(.translocated):
            return "macOS is running Klaxon from a temporary copy. Move Klaxon to Applications and open it from there to turn this on."
        case .temporary(.mountedVolume):
            return "Klaxon is running from the disk image. Drag it to Applications and open it from there to turn this on."
        }
    }
}
