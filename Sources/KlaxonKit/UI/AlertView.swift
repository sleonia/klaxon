import SwiftUI

/// Full-screen alert content: giant title, live countdown, Join/Snooze/Dismiss.
public struct AlertView: View {
    public let meeting: Meeting
    public let background: AlertBackground
    /// Snooze durations (minutes) to offer, in order. 0–3 entries.
    public let snoozeMinutes: [Int]
    public let onJoin: (Meeting) -> Void
    /// `nil` interval means "snooze until the meeting starts".
    public let onSnooze: (Meeting, TimeInterval?) -> Void
    public let onDismiss: (Meeting) -> Void

    /// Buttons ignore taps until the alert has been on screen briefly, so a
    /// click already in flight when it appears (the overlay covers every
    /// Space) can't instantly dismiss it.
    @State private var armed = false
    private static let armingDelay: Duration = .milliseconds(700)

    public init(
        meeting: Meeting,
        background: AlertBackground,
        snoozeMinutes: [Int],
        preArmed: Bool = false,
        onJoin: @escaping (Meeting) -> Void,
        onSnooze: @escaping (Meeting, TimeInterval?) -> Void,
        onDismiss: @escaping (Meeting) -> Void
    ) {
        self.meeting = meeting
        self.background = background
        self.snoozeMinutes = snoozeMinutes
        _armed = State(initialValue: preArmed)
        self.onJoin = onJoin
        self.onSnooze = onSnooze
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            backgroundView

            VStack(spacing: 28) {
                Spacer()

                calendarChip

                Text(meeting.title)
                    .font(.system(size: 64, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 60)

                VStack(spacing: 8) {
                    Text(timeRange)
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    if let location = meeting.location, !location.isEmpty,
                       meeting.link?.url.absoluteString.contains(location) != true {
                        Text(location)
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(countdownText(now: ctx.date))
                        .font(.system(size: 58, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                buttons
                    .padding(.top, 12)

                Spacer()
            }
        }
        .task {
            try? await Task.sleep(for: Self.armingDelay)
            armed = true
        }
    }

    // MARK: - Pieces

    @ViewBuilder private var backgroundView: some View {
        switch background {
        case .theme(let theme):
            theme.gradient.ignoresSafeArea()
        case .image(let url):
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    // Scrim keeps white text legible over arbitrary photos.
                    .overlay(Color.black.opacity(0.45).ignoresSafeArea())
            } else {
                Theme.all[0].gradient.ignoresSafeArea()
            }
        }
    }

    private var calendarChip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: meeting.calendarColorHex) ?? .white)
                .frame(width: 10, height: 10)
            Text(meeting.calendarTitle.isEmpty ? "Calendar" : meeting.calendarTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.white.opacity(0.12), in: Capsule())
    }

    private var buttons: some View {
        // Three tiers by priority: a large primary Join, a row of numbered
        // snoozes, then a quiet Dismiss. Every control shows its shortcut so
        // ↵ / ⌘1–3 / esc are discoverable rather than hidden.
        VStack(spacing: 18) {
            if let link = meeting.link {
                joinButton(link)
            }

            // Discrete snooze buttons rather than a Menu: one tap to snooze,
            // and no submenu that a stray click could interact with. Count
            // and durations are user-configurable (0–3 buttons).
            if !snoozeMinutes.isEmpty {
                HStack(spacing: 14) {
                    ForEach(snoozeMinutes.indices, id: \.self) { i in
                        snoozeButton(minutes: snoozeMinutes[i], index: i)
                    }
                }
            }

            dismissButton
        }
        .opacity(armed ? 1 : 0.55)
        .animation(.easeIn(duration: 0.2), value: armed)
    }

    private func joinButton(_ link: MeetingLink) -> some View {
        Button {
            guard armed else { return }
            onJoin(meeting)
        } label: {
            HStack(spacing: 14) {
                Label("Join \(link.serviceName)", systemImage: "video.fill")
                    .font(.system(size: 24, weight: .bold))
                keyHint("↵", tint: background.accent, fill: background.accent.opacity(0.12))
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
        .background(.white, in: Capsule())
        .foregroundStyle(background.accent)
        .keyboardShortcut(.defaultAction)
    }

    private func snoozeButton(minutes: Int, index: Int) -> some View {
        Button {
            guard armed else { return }
            onSnooze(meeting, TimeInterval(minutes) * 60)
        } label: {
            HStack(spacing: 8) {
                Text("Snooze \(minutes)m")
                    .font(.system(size: 18, weight: .semibold))
                keyHint("⌘\(index + 1)", tint: .white, fill: .white.opacity(0.22))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.15), in: Capsule())
        .foregroundStyle(.white)
        // ⌘1/⌘2/⌘3 mirror the visible badges; snooze count is capped at 3.
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
    }

    private var dismissButton: some View {
        Button {
            guard armed else { return }
            onDismiss(meeting)
        } label: {
            HStack(spacing: 8) {
                Text("Dismiss")
                    .font(.system(size: 16, weight: .semibold))
                keyHint("esc", tint: .white.opacity(0.9), fill: .white.opacity(0.16))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.8))
        .keyboardShortcut(.cancelAction)
    }

    /// A small rounded chip showing a key's glyph beside its button.
    private func keyHint(_ text: String, tint: Color, fill: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Formatting

    private var timeRange: String {
        (meeting.startDate..<meeting.endDate)
            .formatted(date: .omitted, time: .shortened)
    }

    /// Just the time-to-start as a bare number (e.g. "1:18" or "1h 5m"), or
    /// "Now" once the meeting has reached its start — no label, by design.
    private func countdownText(now: Date) -> String {
        let dt = meeting.startDate.timeIntervalSince(now)
        return dt >= 1 ? Self.format(dt) : "Now"
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension Color {
    /// Parses "#RRGGBB" (as produced by CalendarService).
    init?(hex: String?) {
        guard var hex else { return nil }
        hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
