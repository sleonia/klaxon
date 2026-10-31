import XCTest
@testable import KlaxonKit

final class NativeAppURLTests: XCTestCase {

    private func native(_ s: String) -> String? {
        NativeAppURL.make(for: URL(string: s)!)?.absoluteString
    }

    // MARK: - Zoom

    func testZoomMeetingWithPasswordAndSubdomain() {
        XCTAssertEqual(
            native("https://us02web.zoom.us/j/1234567890?pwd=abc"),
            "zoommtg://us02web.zoom.us/join?action=join&confno=1234567890&pwd=abc")
    }

    func testZoomMeetingWithoutQuery() {
        XCTAssertEqual(
            native("https://zoom.us/j/1234567890"),
            "zoommtg://zoom.us/join?action=join&confno=1234567890")
    }

    func testZoomGov() {
        XCTAssertEqual(
            native("https://agency.zoomgov.com/j/1234567890"),
            "zoommtg://agency.zoomgov.com/join?action=join&confno=1234567890")
    }

    func testZoomPersonalRoomStaysInBrowser() {
        XCTAssertNil(native("https://zoom.us/my/jane.doe"))
    }

    func testZoomNonMeetingPageStaysInBrowser() {
        XCTAssertNil(native("https://zoom.us/j/not-a-number"))
        XCTAssertNil(native("https://zoom.us/webinar/register/abc"))
    }

    // MARK: - Teams

    func testTeamsSwapsSchemeKeepingEncodedPath() {
        let https = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d"
        XCTAssertEqual(
            native(https),
            "msteams://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d")
    }

    func testTeamsLive() {
        XCTAssertEqual(
            native("https://teams.live.com/meet/9876543210?p=abc"),
            "msteams://teams.live.com/meet/9876543210?p=abc")
    }

    // MARK: - Slack, Jitsi

    func testSlackHuddle() {
        XCTAssertEqual(
            native("https://app.slack.com/huddle/T0123ABC/C0456DEF"),
            "slack://join-huddle?team=T0123ABC&id=C0456DEF")
    }

    func testSlackNonHuddleStaysInBrowser() {
        XCTAssertNil(native("https://acme.slack.com/archives/C0456DEF"))
    }

    func testJitsi() {
        XCTAssertEqual(native("https://meet.jit.si/MyRoom"), "jitsi-meet://meet.jit.si/MyRoom")
    }

    // MARK: - No app

    func testServicesWithoutAppSchemeStayInBrowser() {
        XCTAssertNil(native("https://meet.google.com/abc-defg-hij"))
        XCTAssertNil(native("https://example.com/zoom.us/j/123"))
        XCTAssertNil(native("https://notzoom.us/j/1234567890"))
    }
}
