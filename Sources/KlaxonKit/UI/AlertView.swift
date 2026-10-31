import SwiftUI

/// Full-screen alert content. One meeting gets the giant title, live
/// countdown and Join/Snooze/Dismiss; several meetings due together share one
/// countdown above a list with a Join button per row.
public struct AlertView: View {
    /// 1…`AlertPlanner.maxMeetingsPerAlert`, in display order.
    public let meetings: [Meeting]
    /// Meetings due together but left off the alert (over the cap).
    public let skippedCount: Int
    public let background: AlertBackground
    /// Snooze durations (minutes) to offer, in order. 0–3 entries.
    public let snoozeMinutes: [Int]
    public let onJoin: (Meeting) -> Void
    /// Applies to every meeting on the alert. `nil` interval means "snooze
    /// until the meeting starts".
    public let onSnooze: (TimeInterval?) -> Void
    /// Applies to every meeting on the alert.
    public let onDismiss: () -> Void

    /// Buttons ignore taps until the alert has been on screen briefly, so a
    /// click already in flight when it appears (the overlay covers every
    /// Space) can't instantly dismiss it.
    @State private var armed = false
    private static let armingDelay: Duration = .milliseconds(700)

    public init(
        meetings: [Meeting],
        skippedCount: Int = 0,
        background: AlertBackground,
        snoozeMinutes: [Int],
        preArmed: Bool = false,
        onJoin: @escaping (Meeting) -> Void,
        onSnooze: @escaping (TimeInterval?) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        precondition(!meetings.isEmpty, "an alert needs at least one meeting")
        self.meetings = meetings
        self.skippedCount = skippedCount
        self.background = background
        self.snoozeMinutes = snoozeMinutes
        _armed = State(initialValue: preArmed)
        self.onJoin = onJoin
        self.onSnooze = onSnooze
        self.onDismiss = onDismiss
    }

    private var isGroup: Bool { meetings.count > 1 }

    /// The soonest start on the alert; the countdown runs to it.
    private var firstStart: Date { meetings.map(\.startDate).min() ?? meetings[0].startDate }

    public var body: some View {
        ZStack {
            backgroundView

            if isGroup {
                groupLayout
            } else {
                singleLayout(meetings[0])
            }
        }
        .task {
            try? await Task.sleep(for: Self.armingDelay)
            armed = true
        }
    }

    // MARK: - Layouts

    private func singleLayout(_ meeting: Meeting) -> some View {
        VStack(spacing: 28) {
            Spacer()

            calendarChip(meeting)

            Text(meeting.title)
                .font(.system(size: 64, weight: .heavy))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.4)
                .foregroundStyle(.white)
                .padding(.horizontal, 60)

            VStack(spacing: 8) {
                Text(Self.timeRange(meeting))
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                if let location = Self.visibleLocation(meeting) {
                    Text(location)
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            countdown

            VStack(spacing: 18) {
                if let link = meeting.link {
                    joinButton(meeting, link: link)
                }
                snoozeRow
                dismissButton(label: "Dismiss")
            }
            .modifier(ArmedStyle(armed: armed))
            .padding(.top, 12)

            Spacer()
        }
    }

    private var groupLayout: some View {
        // Four rows plus the shared controls must fit a 13" laptop screen,
        // so the group layout tightens its spacing at the cap.
        let tight = meetings.count >= AlertPlanner.maxMeetingsPerAlert
        return VStack(spacing: tight ? 16 : 22) {
            Spacer()

            groupChip

            countdown

            VStack(spacing: 10) {
                ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                    groupRow(meeting, index: index)
                }
            }
            .frame(maxWidth: 860)
            .padding(.horizontal, 60)
            .modifier(ArmedStyle(armed: armed))

            if skippedCount > 0 {
                Text("+\(skippedCount) more at \(Self.clock(firstStart)) not shown")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }

            VStack(spacing: 16) {
                snoozeRow
                dismissButton(label: "Dismiss all")
            }
            .modifier(ArmedStyle(armed: armed))
            .padding(.top, 4)

            Spacer()
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

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(countdownText(now: ctx.date))
                .font(.system(size: 58, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    private func calendarChip(_ meeting: Meeting) -> some View {
        HStack(spacing: 8) {
            calendarDot(meeting)
            Text(meeting.calendarTitle.isEmpty ? "Calendar" : meeting.calendarTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .chipBackground()
    }

    /// "3 meetings at 10:00" (or "from 10:00" when the starts differ). The
    /// count includes skipped meetings, so the header never undercounts.
    private var groupChip: some View {
        let total = meetings.count + skippedCount
        let sameStart = Set(meetings.map(\.startDate)).count == 1
        return Text("\(total) meetings \(sameStart ? "at" : "from") \(Self.clock(firstStart))")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .chipBackground()
    }

    private func calendarDot(_ meeting: Meeting) -> some View {
        Circle()
            .fill(Color(hex: meeting.calendarColorHex) ?? .white)
            .frame(width: 10, height: 10)
    }

    private func groupRow(_ meeting: Meeting, index: Int) -> some View {
        HStack(spacing: 18) {
            calendarDot(meeting)

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.system(size: 30, weight: .heavy))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(rowDetail(meeting))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let link = meeting.link {
                rowJoinButton(meeting, link: link, index: index)
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .padding(.vertical, 16)
        .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func rowDetail(_ meeting: Meeting) -> String {
        var parts: [String] = []
        if !meeting.calendarTitle.isEmpty { parts.append(meeting.calendarTitle) }
        parts.append(Self.timeRange(meeting))
        if let location = Self.visibleLocation(meeting) { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var snoozeRow: some View {
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
    }

    // Three tiers by priority: a large primary Join, a row of numbered
    // snoozes, then a quiet Dismiss. Every control shows its shortcut so
    // ↵ / ⌘1–3 / esc are discoverable rather than hidden.
    private func joinButton(_ meeting: Meeting, link: MeetingLink) -> some View {
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

    /// Row 1 joins on ↵ like a single alert; rows 2–4 on their bare digit,
    /// which can't clash with the ⌘-digit snoozes.
    private func rowJoinButton(_ meeting: Meeting, link: MeetingLink, index: Int) -> some View {
        let shortcut = index == 0
            ? KeyboardShortcut.defaultAction
            : KeyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        return Button {
            guard armed else { return }
            onJoin(meeting)
        } label: {
            HStack(spacing: 10) {
                Label("Join \(link.serviceName)", systemImage: "video.fill")
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)
                keyHint(index == 0 ? "↵" : "\(index + 1)",
                        tint: background.accent, fill: background.accent.opacity(0.12))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(.white, in: Capsule())
        .foregroundStyle(background.accent)
        .keyboardShortcut(shortcut)
        .fixedSize()
    }

    private func snoozeButton(minutes: Int, index: Int) -> some View {
        Button {
            guard armed else { return }
            onSnooze(TimeInterval(minutes) * 60)
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

    private func dismissButton(label: String) -> some View {
        Button {
            guard armed else { return }
            onDismiss()
        } label: {
            HStack(spacing: 8) {
                Text(label)
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

    private static func timeRange(_ meeting: Meeting) -> String {
        (meeting.startDate..<meeting.endDate)
            .formatted(date: .omitted, time: .shortened)
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// The location, unless it is empty or just repeats the call link.
    private static func visibleLocation(_ meeting: Meeting) -> String? {
        guard let location = meeting.location, !location.isEmpty,
              meeting.link?.url.absoluteString.contains(location) != true else { return nil }
        return location
    }

    /// Just the time-to-start as a bare number (e.g. "1:18" or "1h 5m"), or
    /// "Now" once the (first) meeting has reached its start — no label, by design.
    private func countdownText(now: Date) -> String {
        let dt = firstStart.timeIntervalSince(now)
        return dt >= 1 ? Self.format(dt) : "Now"
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Dims controls until the arming delay passes, so they visibly come alive.
private struct ArmedStyle: ViewModifier {
    let armed: Bool
    func body(content: Content) -> some View {
        content
            .opacity(armed ? 1 : 0.55)
            .animation(.easeIn(duration: 0.2), value: armed)
    }
}

private extension View {
    func chipBackground() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.white.opacity(0.12), in: Capsule())
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
