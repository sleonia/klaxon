import AppKit

/// Plays macOS system alert sounds by name.
@MainActor
public enum SoundPlayer {

    /// Basenames of the built-in system sounds (e.g. "Glass", "Sosumi").
    public static let systemSoundNames: [String] = {
        let dir = "/System/Library/Sounds"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return files
            .filter { $0.hasSuffix(".aiff") }
            .map { String($0.dropLast(".aiff".count)) }
            .sorted()
    }()

    private static var current: NSSound?

    /// Plays the named system sound; empty name is silence.
    public static func play(_ name: String) {
        guard !name.isEmpty else { return }
        current?.stop()
        guard let sound = NSSound(named: name) else { return }
        current = sound
        sound.play()
    }
}
