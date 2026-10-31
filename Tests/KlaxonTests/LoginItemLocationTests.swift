import XCTest
@testable import KlaxonKit

final class LoginItemLocationTests: XCTestCase {

    private let home = "/Users/alex"

    private func classify(_ path: String, readOnly: Bool = false) -> LoginItemLocation {
        LoginItemLocation.classify(bundlePath: path, homeDirectory: home,
                                   isOnReadOnlyVolume: readOnly)
    }

    func testSystemApplicationsFolder() {
        XCTAssertEqual(classify("/Applications/Klaxon.app"), .applications)
        XCTAssertEqual(classify("/Applications/Utilities/Klaxon.app"), .applications)
    }

    func testUserApplicationsFolder() {
        XCTAssertEqual(classify("/Users/alex/Applications/Klaxon.app"), .applications)
    }

    func testTrailingSlashAndDotSegmentsAreNormalized() {
        XCTAssertEqual(classify("/Applications/./Klaxon.app/"), .applications)
    }

    func testTranslocatedDownloadIsTemporary() {
        let path = "/private/var/folders/5z/abc/T/AppTranslocation/1B2C-UUID/d/Klaxon.app"
        XCTAssertEqual(classify(path), .temporary(.translocated))
        XCTAssertFalse(classify(path).canRegister)
    }

    func testReadOnlyDiskImageIsTemporary() {
        let location = classify("/Volumes/Klaxon/Klaxon.app", readOnly: true)
        XCTAssertEqual(location, .temporary(.mountedVolume))
        XCTAssertFalse(location.canRegister)
    }

    func testApplicationsFolderOnAnotherWritableVolume() {
        XCTAssertEqual(classify("/Volumes/Data/Applications/Klaxon.app"), .applications)
    }

    func testOtherFolderOnAnotherWritableVolumeIsElsewhere() {
        XCTAssertEqual(classify("/Volumes/Data/Stuff/Klaxon.app"), .elsewhere)
    }

    func testReadOnlyFlagOnlyMattersForOtherVolumes() {
        XCTAssertEqual(classify("/Applications/Klaxon.app", readOnly: true), .applications)
    }

    func testBuildFolderIsElsewhereButRegistrable() {
        let location = classify("/Users/alex/Projects/klaxon/build/Klaxon.app")
        XCTAssertEqual(location, .elsewhere)
        XCTAssertTrue(location.canRegister)
        XCTAssertNotNil(location.explanation)
    }

    func testFolderMerelyNamedLikeApplicationsIsNotApplications() {
        XCTAssertEqual(classify("/ApplicationsOld/Klaxon.app"), .elsewhere)
        XCTAssertEqual(classify("/Users/alex/ApplicationsBackup/Klaxon.app"), .elsewhere)
    }

    func testApplicationsHasNoExplanation() {
        XCTAssertNil(classify("/Applications/Klaxon.app").explanation)
        XCTAssertTrue(classify("/Applications/Klaxon.app").canRegister)
    }
}
