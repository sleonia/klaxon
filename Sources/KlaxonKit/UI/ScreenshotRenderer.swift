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
        write(alert([sample], themeID: "classic"), size: overlaySize,
              to: "\(directory)/alert-classic.png")
        write(alert([sample], themeID: "ocean"), size: overlaySize,
              to: "\(directory)/alert-ocean.png")
        write(alert(groupSample(), themeID: "classic"), size: overlaySize,
              to: "\(directory)/alert-multi.png")
    }

    /// Several meetings due together, as one grouped alert shows them.
    private static func groupSample() -> [Meeting] {
        let start = Date().addingTimeInterval(120)
        func meeting(_ title: String, _ calendar: String, _ color: String,
                     minutes: Double, service: String?, location: String? = nil) -> Meeting {
            Meeting(
                eventIdentifier: title, title: title,
                startDate: start, endDate: start.addingTimeInterval(minutes * 60),
                calendarTitle: calendar, calendarColorHex: color, location: location,
                link: service.map {
                    MeetingLink(serviceName: $0, url: URL(string: "https://example.com/join")!)
                })
        }
        return [
            meeting("Design Review", "Work", "#4A90D9", minutes: 30, service: "Google Meet"),
            meeting("Hiring Sync", "Recruiting", "#34C759", minutes: 60, service: "Microsoft Teams"),
            meeting("Quarterly Check-in", "Sales", "#AF52DE", minutes: 45, service: nil,
                    location: "Room 4B"),
        ]
    }

    private static func alert(_ meetings: [Meeting], skippedCount: Int = 0,
                              themeID: String) -> some View {
        AlertView(
            meetings: meetings,
            skippedCount: skippedCount,
            background: .theme(Theme.theme(id: themeID)),
            snoozeMinutes: [1, 3, 5],
            preArmed: true,
            onJoin: { _ in }, onSnooze: { _ in }, onDismiss: {})
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
