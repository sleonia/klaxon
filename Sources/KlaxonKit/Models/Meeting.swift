import Foundation

/// A detected video-conferencing (or generic) link attached to a meeting.
public struct MeetingLink: Equatable, Sendable {
    public let serviceName: String
    public let url: URL

    public init(serviceName: String, url: URL) {
        self.serviceName = serviceName
        self.url = url
    }
}

/// A calendar event occurrence, normalized out of EventKit.
///
/// `id` is unique per *occurrence*: recurring events share an
/// `eventIdentifier`, so the start date is folded into the id.
public struct Meeting: Identifiable, Equatable, Sendable {
    public let id: String
    public let eventIdentifier: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let isDeclined: Bool
    public let calendarID: String
    public let calendarTitle: String
    public let calendarColorHex: String?
    public let location: String?
    public let link: MeetingLink?

    public init(
        eventIdentifier: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        isDeclined: Bool = false,
        calendarID: String = "",
        calendarTitle: String = "",
        calendarColorHex: String? = nil,
        location: String? = nil,
        link: MeetingLink? = nil
    ) {
        self.id = "\(eventIdentifier)#\(startDate.timeIntervalSince1970)"
        self.eventIdentifier = eventIdentifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.isDeclined = isDeclined
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.calendarColorHex = calendarColorHex
        self.location = location
        self.link = link
    }
}
