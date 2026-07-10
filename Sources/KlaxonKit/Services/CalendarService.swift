import AppKit
import EventKit

public struct CalendarInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let colorHex: String?
    public let sourceTitle: String
}

/// EventKit boundary: permission, fetching, and change monitoring.
/// Everything downstream works on `[Meeting]` values, never `EKEvent`s.
@MainActor
public final class CalendarService {

    private let store = EKEventStore()
    // Written once in init, read in deinit — no concurrent access window.
    nonisolated(unsafe) private var changeObserver: NSObjectProtocol?
    /// An EKEventStore created before access was granted returns empty results
    /// until reset(). We reset exactly once, the first time we observe access.
    private var didResetAfterGrant = false

    /// Invoked (on the main actor) whenever the event database changes.
    public var onChange: (() -> Void)?

    public init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    // MARK: - Permission

    public var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    public var hasAccess: Bool { authorizationStatus == .fullAccess }

    /// Requests full calendar access (macOS 14+ flow). Returns success.
    public func requestAccess() async -> Bool {
        if hasAccess {
            ensureStoreFresh()
            return true
        }
        do {
            let granted = try await store.requestFullAccessToEvents()
            if granted { ensureStoreFresh() }
            return granted
        } catch {
            NSLog("Klaxon: calendar access request failed: \(error)")
            return false
        }
    }

    /// Resets the store once after access is first observed, so results are
    /// not stale when access was granted externally (e.g. System Settings)
    /// after this store was created.
    private func ensureStoreFresh() {
        guard hasAccess, !didResetAfterGrant else { return }
        store.reset()
        didResetAfterGrant = true
    }

    // MARK: - Fetching

    /// Events from one hour ago (to catch in-progress meetings within the
    /// planner's grace window) through `windowHours` ahead, as Meetings.
    public func fetchMeetings(windowHours: Int = 48, now: Date = Date()) -> [Meeting] {
        guard hasAccess else { return [] }
        ensureStoreFresh()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(TimeInterval(windowHours) * 3600),
            calendars: nil)
        return store.events(matching: predicate)
            .compactMap { Self.meeting(from: $0) }
            .sorted { $0.startDate < $1.startDate }
    }

    public func allCalendars() -> [CalendarInfo] {
        guard hasAccess else { return [] }
        ensureStoreFresh()
        return store.calendars(for: .event)
            .map {
                CalendarInfo(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    colorHex: Self.hex(from: $0.color),
                    sourceTitle: $0.source?.title ?? "")
            }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    // MARK: - Mapping

    private static func meeting(from event: EKEvent) -> Meeting? {
        guard let start = event.startDate, let end = event.endDate else { return nil }
        // Never alert for a cancelled event.
        if event.status == .canceled { return nil }
        let declined = event.attendees?
            .first(where: \.isCurrentUser)?
            .participantStatus == .declined
        return Meeting(
            eventIdentifier: event.eventIdentifier ?? event.calendarItemIdentifier,
            title: event.title ?? "Untitled event",
            startDate: start,
            endDate: end,
            isAllDay: event.isAllDay,
            isDeclined: declined,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            calendarTitle: event.calendar?.title ?? "",
            calendarColorHex: hex(from: event.calendar?.color),
            location: event.location,
            link: MeetingLinkParser.detect(
                urlField: event.url, location: event.location, notes: event.notes)
        )
    }

    private static func hex(from color: NSColor?) -> String? {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
