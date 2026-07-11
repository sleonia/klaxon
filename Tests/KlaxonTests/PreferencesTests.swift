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

    // Exercises the property setter's didSet (the real crash site): before the
    // fix, assigning snoozeMinutes recursed into didSet forever (stack
    // overflow). This must terminate and sanitize.
    @MainActor
    func testAssigningSnoozeMinutesSanitizesWithoutRecursing() {
        let defaults = UserDefaults(suiteName: "klaxon.test.\(UUID().uuidString)")!
        let prefs = Preferences(defaults: defaults)

        prefs.snoozeMinutes = [10, 20, 30, 40]   // over the max of 3
        XCTAssertEqual(prefs.snoozeMinutes, [10, 20, 30])

        prefs.snoozeMinutes = []                  // empty is allowed
        XCTAssertEqual(prefs.snoozeMinutes, [])

        prefs.snoozeMinutes = [0, 200]            // clamp each value into range
        XCTAssertEqual(prefs.snoozeMinutes, [1, 120])

        prefs.snoozeMinutes = [1, 3, 5]           // already-clean assignment
        XCTAssertEqual(prefs.snoozeMinutes, [1, 3, 5])
    }

    @MainActor
    func testMenuBarIconOnlyDefaultsOffAndPersists() {
        let defaults = UserDefaults(suiteName: "klaxon.test.\(UUID().uuidString)")!
        XCTAssertFalse(Preferences(defaults: defaults).menuBarIconOnly)

        Preferences(defaults: defaults).menuBarIconOnly = true
        // A fresh instance reads back the persisted value.
        XCTAssertTrue(Preferences(defaults: defaults).menuBarIconOnly)
    }
}
