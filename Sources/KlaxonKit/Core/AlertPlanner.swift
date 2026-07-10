import Foundation

/// What the scheduler should do next: show `meeting`'s alert at `fireDate`.
public struct AlertPlan: Equatable, Sendable {
    public let meeting: Meeting
    public let fireDate: Date

    public init(meeting: Meeting, fireDate: Date) {
        self.meeting = meeting
        self.fireDate = fireDate
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

        return meetings
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
            .map { m -> AlertPlan in
                let natural = snoozes[m.id] ?? m.startDate.addingTimeInterval(-config.leadTime)
                return AlertPlan(meeting: m, fireDate: max(natural, now))
            }
            .min { a, b in
                if a.fireDate != b.fireDate { return a.fireDate < b.fireDate }
                if a.meeting.startDate != b.meeting.startDate {
                    return a.meeting.startDate < b.meeting.startDate
                }
                return a.meeting.id < b.meeting.id
            }
    }
}
