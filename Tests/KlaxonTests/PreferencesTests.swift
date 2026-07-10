import XCTest
@testable import KlaxonKit

final class PreferencesTests: XCTestCase {

    func testSnoozeClampsToMaxThreeEntries() {
        let result = Preferences.sanitizeSnooze([1, 2, 3, 4, 5])
        XCTAssertEqual(result, [1, 2, 3])
    }

    func testSnoozeClampsEachValueToValidRange() {
        XCTAssertEqual(Preferences.sanitizeSnooze([0, -5, 999]), [1, 1, 120])
    }

    func testSnoozeAllowsEmpty() {
        XCTAssertEqual(Preferences.sanitizeSnooze([]), [])
    }

    func testSnoozePreservesOrder() {
        XCTAssertEqual(Preferences.sanitizeSnooze([5, 1, 3]), [5, 1, 3])
    }
}
