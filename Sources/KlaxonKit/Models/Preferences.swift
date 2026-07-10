import Foundation

public extension Notification.Name {
    /// Posted whenever any preference changes; the app replans on it.
    static let prefsChanged = Notification.Name("com.sleonia.Klaxon.prefsChanged")
}

/// UserDefaults-backed settings. Every mutation persists immediately and
/// posts `.prefsChanged` so the scheduler can recompute.
@MainActor
public final class Preferences: ObservableObject {

    private enum Key {
        static let leadTimeMinutes = "leadTimeMinutes"
        static let includeAllDay = "includeAllDay"
        static let includeDeclined = "includeDeclined"
        static let disabledCalendarIDs = "disabledCalendarIDs"
        static let soundName = "soundName"
        static let themeID = "themeID"
        static let launchAtLogin = "launchAtLogin"
        static let paused = "paused"
        static let snoozeMinutes = "snoozeMinutes"
        static let customBackgroundPath = "customBackgroundPath"
    }

    /// Overlay themeID sentinel selecting the user's custom background image.
    public static let customThemeID = "custom"

    /// Max number of snooze buttons shown on the alert.
    public nonisolated static let maxSnoozeButtons = 3

    private let defaults: UserDefaults

    @Published public var leadTimeMinutes: Double {
        didSet { defaults.set(leadTimeMinutes, forKey: Key.leadTimeMinutes); changed() }
    }
    @Published public var includeAllDay: Bool {
        didSet { defaults.set(includeAllDay, forKey: Key.includeAllDay); changed() }
    }
    @Published public var includeDeclined: Bool {
        didSet { defaults.set(includeDeclined, forKey: Key.includeDeclined); changed() }
    }
    @Published public var disabledCalendarIDs: Set<String> {
        didSet { defaults.set(Array(disabledCalendarIDs), forKey: Key.disabledCalendarIDs); changed() }
    }
    /// Empty string means "no sound".
    @Published public var soundName: String {
        didSet { defaults.set(soundName, forKey: Key.soundName); changed() }
    }
    @Published public var themeID: String {
        didSet { defaults.set(themeID, forKey: Key.themeID); changed() }
    }
    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin); changed() }
    }
    @Published public var paused: Bool {
        didSet { defaults.set(paused, forKey: Key.paused); changed() }
    }
    /// Snooze durations (minutes) offered on the alert, in order. 0–3 entries.
    @Published public var snoozeMinutes: [Int] {
        didSet {
            snoozeMinutes = Self.sanitizeSnooze(snoozeMinutes)
            defaults.set(snoozeMinutes, forKey: Key.snoozeMinutes)
            changed()
        }
    }
    /// File path to a custom overlay background image ("" when unset).
    @Published public var customBackgroundPath: String {
        didSet { defaults.set(customBackgroundPath, forKey: Key.customBackgroundPath); changed() }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        leadTimeMinutes = defaults.object(forKey: Key.leadTimeMinutes) as? Double ?? 1
        includeAllDay = defaults.bool(forKey: Key.includeAllDay)
        includeDeclined = defaults.bool(forKey: Key.includeDeclined)
        disabledCalendarIDs = Set(defaults.stringArray(forKey: Key.disabledCalendarIDs) ?? [])
        soundName = defaults.object(forKey: Key.soundName) as? String ?? "Glass"
        themeID = defaults.object(forKey: Key.themeID) as? String ?? "classic"
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        paused = defaults.bool(forKey: Key.paused)
        let stored = defaults.array(forKey: Key.snoozeMinutes) as? [Int]
        snoozeMinutes = Self.sanitizeSnooze(stored ?? [1, 3, 5])
        customBackgroundPath = defaults.string(forKey: Key.customBackgroundPath) ?? ""
    }

    /// Clamps to at most `maxSnoozeButtons` entries, each a positive minute
    /// value (1–120), preserving order.
    nonisolated static func sanitizeSnooze(_ values: [Int]) -> [Int] {
        Array(values.map { min(max($0, 1), 120) }.prefix(maxSnoozeButtons))
    }

    public var plannerConfig: PlannerConfig {
        PlannerConfig(
            leadTime: leadTimeMinutes * 60,
            includeAllDay: includeAllDay,
            includeDeclined: includeDeclined,
            disabledCalendarIDs: disabledCalendarIDs,
            paused: paused
        )
    }

    private func changed() {
        NotificationCenter.default.post(name: .prefsChanged, object: self)
    }
}
