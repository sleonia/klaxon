import XCTest
@testable import KlaxonKit

final class MeetingLinkParserTests: XCTestCase {

    // MARK: - Field extraction

    func testZoomInURLField() {
        let l = MeetingLinkParser.detect(
            urlField: URL(string: "https://us02web.zoom.us/j/1234567890?pwd=abc"),
            location: nil, notes: nil)
        XCTAssertEqual(l?.serviceName, "Zoom")
        XCTAssertEqual(l?.url.absoluteString, "https://us02web.zoom.us/j/1234567890?pwd=abc")
    }

    func testSchemelessMeetInLocationGetsHTTPS() {
        let l = MeetingLinkParser.detect(
            urlField: nil,
            location: "meet.google.com/abc-defg-hij", notes: nil)
        XCTAssertEqual(l?.serviceName, "Google Meet")
        XCTAssertEqual(l?.url.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testTeamsInNotes() {
        let notes = """
        Agenda: roadmap.
        Join here: https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d
        """
        let l = MeetingLinkParser.detect(urlField: nil, location: nil, notes: notes)
        XCTAssertEqual(l?.serviceName, "Microsoft Teams")
    }

    // MARK: - Precedence

    func testURLFieldWinsOverNotes() {
        let l = MeetingLinkParser.detect(
            urlField: URL(string: "https://company.webex.com/meet/jdoe"),
            location: nil,
            notes: "backup: https://zoom.us/j/999")
        XCTAssertEqual(l?.serviceName, "Webex")
    }

    func testKnownServiceInNotesBeatsGenericURLField() {
        let l = MeetingLinkParser.detect(
            urlField: URL(string: "https://example.com/agenda"),
            location: nil,
            notes: "join: https://zoom.us/j/123456")
        XCTAssertEqual(l?.serviceName, "Zoom")
    }

    func testGenericLinkFallback() {
        let l = MeetingLinkParser.detect(
            urlField: URL(string: "https://example.com/some-call"),
            location: "Room 4", notes: "no video link here")
        XCTAssertEqual(l?.serviceName, "Link")
        XCTAssertEqual(l?.url.absoluteString, "https://example.com/some-call")
    }

    func testNoLink() {
        XCTAssertNil(MeetingLinkParser.detect(urlField: nil, location: "Room 4", notes: "bring laptop"))
    }

    func testBareServiceDomainMentionIsNotALink() {
        // A prose mention of a service with no meeting path is not joinable.
        XCTAssertNil(MeetingLinkParser.detect(
            urlField: nil, location: nil, notes: "We usually meet on zoom.us — details TBD"))
    }

    func testBareDomainDoesNotPreemptRealLink() {
        let l = MeetingLinkParser.detect(
            urlField: nil, location: nil,
            notes: "hosted on zoom.us. Link: https://zoom.us/j/999888777")
        XCTAssertEqual(l?.serviceName, "Zoom")
        XCTAssertEqual(l?.url.absoluteString, "https://zoom.us/j/999888777")
    }

    // MARK: - Robustness

    func testTrailingPunctuationStripped() {
        let l = MeetingLinkParser.detect(
            urlField: nil, location: nil,
            notes: "Call: <https://zoom.us/j/123456789>.")
        XCTAssertEqual(l?.serviceName, "Zoom")
        XCTAssertEqual(l?.url.absoluteString, "https://zoom.us/j/123456789")
    }

    func testFirstServiceLinkInFieldWins() {
        let l = MeetingLinkParser.detect(
            urlField: nil, location: nil,
            notes: "primary https://meet.google.com/aaa-bbbb-ccc backup https://zoom.us/j/1")
        XCTAssertEqual(l?.serviceName, "Google Meet")
    }

    // MARK: - Service coverage

    func testServiceTableCoversThirtyPlusServices() {
        XCTAssertGreaterThanOrEqual(MeetingLinkParser.serviceCount, 30)
    }

    func testRepresentativeServiceSample() {
        let cases: [(String, String)] = [
            ("https://zoomgov.com/j/123", "Zoom"),
            ("https://teams.live.com/meet/9", "Microsoft Teams"),
            ("https://meet.jit.si/MyRoom", "Jitsi"),
            ("https://whereby.com/myroom", "Whereby"),
            ("https://app.gather.town/app/x/y", "Gather"),
            ("https://join.skype.com/abc", "Skype"),
            ("https://facetime.apple.com/join#v=1", "FaceTime"),
            ("https://chime.aws/123", "Amazon Chime"),
            ("https://app.slack.com/huddle/T0/C0", "Slack"),
            ("https://discord.gg/abc", "Discord"),
            ("https://team.gotomeeting.com/join/1", "GoToMeeting"),
            ("https://meet.starleaf.com/1", "StarLeaf"),
            ("https://acme.daily.co/standup", "Daily"),
            ("https://riverside.fm/studio/x", "Riverside"),
            ("https://meeting.zoho.com/join?x=1", "Zoho Meeting"),
        ]
        for (raw, expected) in cases {
            let l = MeetingLinkParser.detect(urlField: nil, location: nil, notes: raw)
            XCTAssertEqual(l?.serviceName, expected, "for \(raw)")
        }
    }
}
