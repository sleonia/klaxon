import XCTest
@testable import KlaxonKit

final class MeetingTests: XCTestCase {
    func testOccurrenceIDIncludesStartDate() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let m = Meeting(
            eventIdentifier: "EV-1",
            title: "Standup",
            startDate: start,
            endDate: start.addingTimeInterval(1800)
        )
        XCTAssertEqual(m.id, "EV-1#1000000.0")
    }

    func testRecurringOccurrencesGetDistinctIDs() {
        let day: TimeInterval = 86_400
        let start = Date(timeIntervalSince1970: 1_000_000)
        let a = Meeting(eventIdentifier: "EV-1", title: "Standup", startDate: start, endDate: start.addingTimeInterval(1800))
        let b = Meeting(eventIdentifier: "EV-1", title: "Standup", startDate: start.addingTimeInterval(day), endDate: start.addingTimeInterval(day + 1800))
        XCTAssertNotEqual(a.id, b.id)
    }
}
