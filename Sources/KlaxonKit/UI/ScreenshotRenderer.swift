import SwiftUI

/// Renders the app's real SwiftUI views to PNGs offscreen (via ImageRenderer)
/// for the README, so screenshots stay in sync with the actual UI and don't
/// require Screen Recording permission. Invoked by `Klaxon --screenshot <dir>`.
@MainActor
public enum ScreenshotRenderer {

    public static func render(to directory: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let sample = Meeting(
            eventIdentifier: "sample",
            title: "Design Review",
            startDate: Date().addingTimeInterval(120),
            endDate: Date().addingTimeInterval(120 + 1800),
            calendarTitle: "Work",
            calendarColorHex: "#4A90D9",
            link: MeetingLink(serviceName: "Video Call",
                              url: URL(string: "https://example.com/join")!))

        let overlaySize = CGSize(width: 1280, height: 800)
        write(alert(sample, themeID: "classic"), size: overlaySize,
              to: "\(directory)/alert-classic.png")
        write(alert(sample, themeID: "ocean"), size: overlaySize,
              to: "\(directory)/alert-ocean.png")
    }

    private static func alert(_ meeting: Meeting, themeID: String) -> some View {
        AlertView(
            meeting: meeting,
            background: .theme(Theme.theme(id: themeID)),
            snoozeMinutes: [1, 3, 5],
            preArmed: true,
            onJoin: { _ in }, onSnooze: { _, _ in }, onDismiss: { _ in })
    }

    private static func write(_ view: some View, size: CGSize, to path: String) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            NSLog("Klaxon: failed to render screenshot \(path)")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
