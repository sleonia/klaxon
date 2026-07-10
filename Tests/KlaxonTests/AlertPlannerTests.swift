import XCTest
@testable import KlaxonKit

final class AlertPlannerTests: XCTestCase {

    let now = Date(timeIntervalSince1970: 1_752_000_000)

    func meeting(
        _ id: String = "M",
        startsIn: TimeInterval,
        duration: TimeInterval = 1800,
        isAllDay: Bool = false,
        isDeclined: Bool = false,
        calendarID: String = "cal-1"
    ) -> Meeting {
        Meeting(
            eventIdentifier: id,
            title: "Meeting \(id)",
            startDate: now.addingTimeInterval(startsIn),
            endDate: now.addingTimeInterval(startsIn + duration),
            isAllDay: isAllDay,
            isDeclined: isDeclined,
            calendarID: calendarID
        )
    }

    var config: PlannerConfig {
        PlannerConfig(
            leadTime: 60,
            includeAllDay: false,
            includeDeclined: false,
            disabledCalendarIDs: [],
            paused: false
        )
    }

    func plan(_ meetings: [Meeting], config: PlannerConfig? = nil,
              snoozes: [String: Date] = [:], dismissed: Set<String> = []) -> AlertPlan? {
        AlertPlanner.nextAlert(
            meetings: meetings, config: config ?? self.config,
            snoozes: snoozes, dismissed: dismissed, now: now)
    }

    // MARK: - Basics

    func testFireDateIsLeadTimeBeforeStart() {
        let m = meeting(startsIn: 600)
        let p = plan([m])
        XCTAssertEqual(p?.meeting, m)
        XCTAssertEqual(p?.fireDate, m.startDate.addingTimeInterval(-60))
    }

    func testOverdueAlertClampsToNow() {
        // Starts in 30s with 60s lead: fire date already passed -> now.
        let m = meeting(startsIn: 30)
        XCTAssertEqual(plan([m])?.fireDate, now)
    }

    func testEmptyInputGivesNil() {
        XCTAssertNil(plan([]))
    }

    func testPausedGivesNil() {
        var c = config; c.paused = true
        XCTAssertNil(plan([meeting(startsIn: 600)], config: c))
    }

    // MARK: - Started/ended meetings

    func testMeetingStartedWithinGraceStillAlerts() {
        let m = meeting(startsIn: -120) // started 2 min ago, grace 300
        XCTAssertEqual(plan([m])?.fireDate, now)
    }

    func testMeetingStartedBeyondGraceExcluded() {
        XCTAssertNil(plan([meeting(startsIn: -301)]))
    }

    func testEndedMeetingExcluded() {
        XCTAssertNil(plan([meeting(startsIn: -7200, duration: 1800)]))
    }

    // MARK: - Filters

    func testAllDayExcludedByDefaultIncludedWhenEnabled() {
        let m = meeting(startsIn: 600, isAllDay: true)
        XCTAssertNil(plan([m]))
        var c = config; c.includeAllDay = true
        XCTAssertNotNil(plan([m], config: c))
    }

    func testDeclinedExcludedByDefaultIncludedWhenEnabled() {
        let m = meeting(startsIn: 600, isDeclined: true)
        XCTAssertNil(plan([m]))
        var c = config; c.includeDeclined = true
        XCTAssertNotNil(plan([m], config: c))
    }

    func testDisabledCalendarExcluded() {
        var c = config; c.disabledCalendarIDs = ["cal-1"]
        XCTAssertNil(plan([meeting(startsIn: 600)], config: c))
    }

    func testDismissedOccurrenceExcluded() {
        let m = meeting(startsIn: 600)
        XCTAssertNil(plan([m], dismissed: [m.id]))
    }

    // The livelock fix routes already-alerted ids through `dismissed`, so the
    // planner must skip an excluded meeting and pick the next, and return nil
    // when every candidate is excluded (no infinite re-fire).
    func testExcludingShownMeetingSelectsNext() {
        let shown = meeting("shown", startsIn: 300)
        let next = meeting("next", startsIn: 900)
        XCTAssertEqual(plan([shown, next], dismissed: [shown.id])?.meeting.eventIdentifier, "next")
    }

    func testAllExcludedGivesNil() {
        let a = meeting("a", startsIn: 300)
        let b = meeting("b", startsIn: 900)
        XCTAssertNil(plan([a, b], dismissed: [a.id, b.id]))
    }

    // MARK: - Snooze

    func testSnoozeExpiryOverridesLeadTime() {
        let m = meeting(startsIn: 600)
        let expiry = now.addingTimeInterval(300)
        XCTAssertEqual(plan([m], snoozes: [m.id: expiry])?.fireDate, expiry)
    }

    func testExpiredSnoozeFiresImmediately() {
        let m = meeting(startsIn: 600)
        let expiry = now.addingTimeInterval(-10)
        XCTAssertEqual(plan([m], snoozes: [m.id: expiry])?.fireDate, now)
    }

    func testSnoozeSurvivesStartedGraceCutoff() {
        // Meeting started 6 min ago (beyond 300s grace) but is still running,
        // and the user snoozed it to fire now. It must NOT be swallowed.
        let m = meeting(startsIn: -360, duration: 1800)
        let expiry = now.addingTimeInterval(-1)
        XCTAssertEqual(plan([m], snoozes: [m.id: expiry])?.meeting, m)
    }

    func testSnoozeCannotResurrectEndedMeeting() {
        // Snoozed but already over -> still excluded by the endDate check.
        let m = meeting(startsIn: -7200, duration: 1800)
        XCTAssertNil(plan([m], snoozes: [m.id: now]))
    }

    // MARK: - Selection

    func testPicksEarliestFireDate() {
        let far = meeting("far", startsIn: 3600)
        let near = meeting("near", startsIn: 600)
        XCTAssertEqual(plan([far, near])?.meeting.eventIdentifier, "near")
    }

    func testSnoozedLaterMeetingCanBeatEarlierOne() {
        // "second" snoozed to fire in 60s; "first" naturally fires in 540s.
        let first = meeting("first", startsIn: 600)
        let second = meeting("second", startsIn: 1200)
        let p = plan([first, second], snoozes: [second.id: now.addingTimeInterval(60)])
        XCTAssertEqual(p?.meeting.eventIdentifier, "second")
    }

    func testTieBreaksByStartDateThenID() {
        // Both fire now (overdue). "a" starts sooner -> wins.
        let a = meeting("a", startsIn: 10)
        let b = meeting("b", startsIn: 20)
        XCTAssertEqual(plan([b, a])?.meeting.eventIdentifier, "a")
        // Identical start: deterministic by id.
        let x = meeting("x", startsIn: 10)
        XCTAssertEqual(plan([x, a])?.meeting.eventIdentifier, "a")
    }
}
