import Foundation

/// Detects video-conferencing links in calendar event fields.
///
/// Precedence: URL field, then location, then notes — the first link that
/// matches a *known* service wins. If no known service is found anywhere,
/// an http(s) URL field is returned as a generic "Link".
public enum MeetingLinkParser {

    private struct Service {
        let name: String
        let hostSuffixes: [String]
        var pathContains: String? = nil
    }

    /// 30+ supported services, matched by host suffix (and optionally path).
    private static let services: [Service] = [
        Service(name: "Zoom", hostSuffixes: ["zoom.us", "zoomgov.com", "zoom.com"]),
        Service(name: "Google Meet", hostSuffixes: ["meet.google.com"]),
        Service(name: "Microsoft Teams", hostSuffixes: ["teams.microsoft.com", "teams.live.com"]),
        Service(name: "Webex", hostSuffixes: ["webex.com"]),
        Service(name: "GoToMeeting", hostSuffixes: ["gotomeeting.com", "gotomeet.me"]),
        Service(name: "GoToWebinar", hostSuffixes: ["gotowebinar.com"]),
        Service(name: "Whereby", hostSuffixes: ["whereby.com"]),
        Service(name: "Jitsi", hostSuffixes: ["meet.jit.si"]),
        Service(name: "Discord", hostSuffixes: ["discord.gg", "discord.com"]),
        Service(name: "Slack", hostSuffixes: ["slack.com"], pathContains: "/huddle"),
        Service(name: "Amazon Chime", hostSuffixes: ["chime.aws"]),
        Service(name: "BlueJeans", hostSuffixes: ["bluejeans.com"]),
        Service(name: "RingCentral", hostSuffixes: ["meetings.ringcentral.com", "v.ringcentral.com"]),
        Service(name: "8x8", hostSuffixes: ["8x8.vc"]),
        Service(name: "Vonage", hostSuffixes: ["meetings.vonage.com"]),
        Service(name: "Lifesize", hostSuffixes: ["lifesizecloud.com", "lifesize.com"]),
        Service(name: "StarLeaf", hostSuffixes: ["meet.starleaf.com"]),
        Service(name: "Skype", hostSuffixes: ["join.skype.com"]),
        Service(name: "Skype for Business", hostSuffixes: ["meet.lync.com"]),
        Service(name: "FaceTime", hostSuffixes: ["facetime.apple.com"]),
        Service(name: "Around", hostSuffixes: ["around.co"]),
        Service(name: "Gather", hostSuffixes: ["gather.town"]),
        Service(name: "Pop", hostSuffixes: ["pop.com"]),
        Service(name: "Tandem", hostSuffixes: ["tandem.chat"]),
        Service(name: "Butter", hostSuffixes: ["butter.us"]),
        Service(name: "Livestorm", hostSuffixes: ["livestorm.co"]),
        Service(name: "Demio", hostSuffixes: ["demio.com"]),
        Service(name: "Zoho Meeting", hostSuffixes: ["meeting.zoho.com"]),
        Service(name: "TeamViewer", hostSuffixes: ["go.teamviewer.com"]),
        Service(name: "Vowel", hostSuffixes: ["vowel.com"]),
        Service(name: "Daily", hostSuffixes: ["daily.co"]),
        Service(name: "Riverside", hostSuffixes: ["riverside.fm"]),
        Service(name: "StreamYard", hostSuffixes: ["streamyard.com"]),
    ]

    /// Number of known services (exposed for tests).
    static var serviceCount: Int { services.count }

    public static func detect(urlField: URL?, location: String?, notes: String?) -> MeetingLink? {
        let fields = [urlField?.absoluteString, location, notes]
        for field in fields {
            guard let text = field, !text.isEmpty else { continue }
            if let link = firstKnownServiceLink(in: text) { return link }
        }
        // Generic fallback: an explicit URL field is still a joinable link.
        if let url = urlField, let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return MeetingLink(serviceName: "Link", url: url)
        }
        return nil
    }

    // MARK: - Extraction

    private static let explicitURLRegex = try! NSRegularExpression(
        pattern: #"https?://[^\s<>"')\]]+"#, options: [.caseInsensitive])

    /// Schemeless domain-WITH-path tokens, e.g. "meet.google.com/abc-def".
    /// The path is required: a bare "zoom.us" mention in prose isn't a
    /// joinable meeting link, and requiring a path stops such mentions from
    /// preempting a real URL elsewhere in the same field.
    /// Lookbehind avoids matching inside emails, paths, or larger hostnames.
    private static let schemelessRegex = try! NSRegularExpression(
        pattern: #"(?<![\w@/.-])(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}/[^\s<>"')\]]+"#, options: [])

    private static func firstKnownServiceLink(in text: String) -> MeetingLink? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        var candidates: [(range: NSRange, raw: String, hasScheme: Bool)] = []
        for m in explicitURLRegex.matches(in: text, range: full) {
            candidates.append((m.range, ns.substring(with: m.range), true))
        }
        let explicitRanges = candidates.map(\.range)
        for m in schemelessRegex.matches(in: text, range: full) {
            let overlapsExplicit = explicitRanges.contains {
                NSIntersectionRange($0, m.range).length > 0
            }
            if !overlapsExplicit {
                candidates.append((m.range, ns.substring(with: m.range), false))
            }
        }
        candidates.sort { $0.range.location < $1.range.location }

        for candidate in candidates {
            var raw = trimTrailingPunctuation(candidate.raw)
            if !candidate.hasScheme { raw = "https://" + raw }
            guard let url = URL(string: raw), let name = serviceName(for: url) else { continue }
            return MeetingLink(serviceName: name, url: url)
        }
        return nil
    }

    private static func trimTrailingPunctuation(_ s: String) -> String {
        var s = s
        while let last = s.last, ".,;:!?'\"”’»)]}>".contains(last) {
            s.removeLast()
        }
        return s
    }

    private static func serviceName(for url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        for service in services {
            let hostMatches = service.hostSuffixes.contains {
                host == $0 || host.hasSuffix("." + $0)
            }
            guard hostMatches else { continue }
            if let needle = service.pathContains, !url.path.contains(needle) { continue }
            return service.name
        }
        return nil
    }
}
