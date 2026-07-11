import XCTest
@testable import KlaxonKit

@MainActor
final class StatusItemControllerTests: XCTestCase {

    private func meeting(_ title: String, startsIn seconds: TimeInterval, now: Date) -> Meeting {
        let start = now.addingTimeInterval(seconds)
        return Meeting(
            eventIdentifier: "t", title: title,
            startDate: start, endDate: start.addingTimeInterval(1800))
    }

    func testShowsMeetingTitleAndCountdown() {
        let now = Date()
        let title = StatusItemController.statusTitle(
            paused: false, meeting: meeting("Standup", startsIn: 600, now: now),
            now: now, iconOnly: false)
        XCTAssertEqual(title, " Standup · in 10m")
    }

    func testShowsNowWhenImminent() {
        let now = Date()
        let title = StatusItemController.statusTitle(
            paused: false, meeting: meeting("Standup", startsIn: 30, now: now),
            now: now, iconOnly: false)
        XCTAssertEqual(title, " Standup · now")
    }

    func testIconOnlyHidesTitleAndCountdown() {
        let now = Date()
        let title = StatusItemController.statusTitle(
            paused: false, meeting: meeting("Secret Board Sync", startsIn: 600, now: now),
            now: now, iconOnly: true)
        XCTAssertEqual(title, "")
    }

    func testIconOnlyStillShowsPaused() {
        XCTAssertEqual(
            StatusItemController.statusTitle(
                paused: true, meeting: nil, now: Date(), iconOnly: true),
            " Paused")
    }

    func testPausedOverridesMeeting() {
        let now = Date()
        let title = StatusItemController.statusTitle(
            paused: true, meeting: meeting("Standup", startsIn: 600, now: now),
            now: now, iconOnly: false)
        XCTAssertEqual(title, " Paused")
    }

    func testNoMeetingIsEmpty() {
        XCTAssertEqual(
            StatusItemController.statusTitle(
                paused: false, meeting: nil, now: Date(), iconOnly: false),
            "")
    }
}
