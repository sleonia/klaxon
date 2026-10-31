import Foundation

/// What the scheduler should do next: show one alert at `fireDate` for
/// every meeting in `meetings` (meetings due together share one alert).
public struct AlertPlan: Equatable, Sendable {
    /// Shown on the alert: 1…`AlertPlanner.maxMeetingsPerAlert`, sorted by
    /// start date, then title, then id.
    public let meetings: [Meeting]
    /// Due at the same time but over the cap; not shown and not re-alerted.
    public let skipped: [Meeting]
    public let fireDate: Date

    /// The first meeting on the alert.
    public var meeting: Meeting { meetings[0] }

    public init(meetings: [Meeting], skipped: [Meeting] = [], fireDate: Date) {
        precondition(!meetings.isEmpty, "an alert needs at least one meeting")
        self.meetings = meetings
        self.skipped = skipped
        self.fireDate = fireDate
    }

    public init(meeting: Meeting, fireDate: Date) {
        self.init(meetings: [meeting], fireDate: fireDate)
    }
}

/// User-facing knobs that shape alert planning.
public struct PlannerConfig: Equatable, Sendable {
    /// Seconds before an event's start to fire the alert.
    public var leadTime: TimeInterval
    public var includeAllDay: Bool
    public var includeDeclined: Bool
    public var disabledCalendarIDs: Set<String>
    public var paused: Bool
    /// Still alert for meetings that started up to this many seconds ago
    /// (e.g. the app launched mid-standup).
    public var startedGrace: TimeInterval

    public init(
        leadTime: TimeInterval,
        includeAllDay: Bool,
        includeDeclined: Bool,
        disabledCalendarIDs: Set<String>,
        paused: Bool,
        startedGrace: TimeInterval = 300
    ) {
        self.leadTime = leadTime
        self.includeAllDay = includeAllDay
        self.includeDeclined = includeDeclined
        self.disabledCalendarIDs = disabledCalendarIDs
        self.paused = paused
        self.startedGrace = startedGrace
    }
}

/// Pure alert planning: no clocks, no EventKit, no timers.
///
/// The scheduler re-invokes this after *any* state change (calendar edits,
/// wake from sleep, preference changes, snooze/dismiss) — recomputing from
/// scratch is what makes the timers drift-proof (plan.md §3b).
public enum AlertPlanner {

    /// Most meetings one alert shows; the rest of the group is skipped.
    public static let maxMeetingsPerAlert = 4

    /// Meetings whose fire dates fall within this many seconds of the
    /// earliest one share its alert (and fire with it, slightly early).
    public static let groupWindow: TimeInterval = 60

    /// - Parameters:
    ///   - snoozes: meeting occurrence id → absolute fire date.
    ///   - dismissed: occurrence ids the user dismissed outright.
    /// - Returns: the next alert to arm, or nil if nothing qualifies.
    public static func nextAlert(
        meetings: [Meeting],
        config: PlannerConfig,
        snoozes: [String: Date],
        dismissed: Set<String>,
        now: Date
    ) -> AlertPlan? {
        guard !config.paused else { return nil }

        let candidates = meetings
            .filter { m in
                if dismissed.contains(m.id) { return false }
                if m.isAllDay && !config.includeAllDay { return false }
                if m.isDeclined && !config.includeDeclined { return false }
                if config.disabledCalendarIDs.contains(m.calendarID) { return false }
                if m.endDate <= now { return false }
                // Drop meetings that started too long ago — UNLESS the user
                // explicitly snoozed one, in which case honor the snooze right
                // up until the meeting actually ends (endDate check above).
                if snoozes[m.id] == nil,
                   m.startDate <= now.addingTimeInterval(-config.startedGrace) {
                    return false
                }
                return true
            }
            .map { m -> (meeting: Meeting, fireDate: Date) in
                let natural = snoozes[m.id] ?? m.startDate.addingTimeInterval(-config.leadTime)
                return (m, max(natural, now))
            }

        guard let fireDate = candidates.map(\.fireDate).min() else { return nil }

        let group = candidates
            .filter { $0.fireDate <= fireDate.addingTimeInterval(groupWindow) }
            .map(\.meeting)
            .sorted { a, b in
                if a.startDate != b.startDate { return a.startDate < b.startDate }
                if a.title != b.title { return a.title < b.title }
                return a.id < b.id
            }

        return AlertPlan(
            meetings: Array(group.prefix(maxMeetingsPerAlert)),
            skipped: Array(group.dropFirst(maxMeetingsPerAlert)),
            fireDate: fireDate)
    }
}
