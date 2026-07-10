import SwiftUI

/// A gradient theme for the full-screen overlay.
public struct Theme: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let gradientTop: Color
    public let gradientBottom: Color

    public var gradient: LinearGradient {
        LinearGradient(
            colors: [gradientTop, gradientBottom],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public static let all: [Theme] = [
        Theme(id: "classic", name: "Classic",
              gradientTop: Color(red: 0.86, green: 0.16, blue: 0.22),
              gradientBottom: Color(red: 0.95, green: 0.45, blue: 0.10)),
        Theme(id: "ocean", name: "Ocean",
              gradientTop: Color(red: 0.05, green: 0.25, blue: 0.55),
              gradientBottom: Color(red: 0.05, green: 0.60, blue: 0.65)),
        Theme(id: "forest", name: "Forest",
              gradientTop: Color(red: 0.05, green: 0.35, blue: 0.22),
              gradientBottom: Color(red: 0.35, green: 0.60, blue: 0.25)),
        Theme(id: "slate", name: "Slate",
              gradientTop: Color(red: 0.15, green: 0.17, blue: 0.22),
              gradientBottom: Color(red: 0.30, green: 0.35, blue: 0.45)),
        Theme(id: "sunset", name: "Sunset",
              gradientTop: Color(red: 0.98, green: 0.36, blue: 0.35),
              gradientBottom: Color(red: 0.55, green: 0.20, blue: 0.55)),
        Theme(id: "grape", name: "Grape",
              gradientTop: Color(red: 0.36, green: 0.16, blue: 0.62),
              gradientBottom: Color(red: 0.66, green: 0.28, blue: 0.80)),
        Theme(id: "rose", name: "Rose",
              gradientTop: Color(red: 0.80, green: 0.20, blue: 0.45),
              gradientBottom: Color(red: 0.98, green: 0.55, blue: 0.55)),
        Theme(id: "aurora", name: "Aurora",
              gradientTop: Color(red: 0.10, green: 0.50, blue: 0.55),
              gradientBottom: Color(red: 0.45, green: 0.25, blue: 0.65)),
        Theme(id: "mono", name: "Mono",
              gradientTop: Color(red: 0.10, green: 0.10, blue: 0.12),
              gradientBottom: Color(red: 0.28, green: 0.28, blue: 0.30)),
        Theme(id: "amber", name: "Amber",
              gradientTop: Color(red: 0.80, green: 0.45, blue: 0.05),
              gradientBottom: Color(red: 0.95, green: 0.72, blue: 0.20)),
    ]

    public static func theme(id: String) -> Theme {
        all.first { $0.id == id } ?? all[0]
    }
}

/// What fills the overlay behind the alert content.
public enum AlertBackground {
    case theme(Theme)
    case image(URL)

    /// Accent used for the prominent Join button's text on its white capsule.
    public var accent: Color {
        switch self {
        case .theme(let t): t.gradientTop
        case .image: Color(red: 0.10, green: 0.10, blue: 0.12)
        }
    }

    /// Resolves the effective background from stored preferences, falling
    /// back to the gradient theme if a custom image is selected but missing.
    @MainActor
    public static func resolve(themeID: String, customBackgroundPath: String) -> AlertBackground {
        if themeID == Preferences.customThemeID, !customBackgroundPath.isEmpty {
            let url = URL(fileURLWithPath: customBackgroundPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return .image(url)
            }
        }
        if themeID == Preferences.randomThemeID {
            return .theme(Theme.all.randomElement() ?? Theme.all[0])
        }
        return .theme(Theme.theme(id: themeID))
    }
}
