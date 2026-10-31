import Foundation

/// Rewrites a meeting's https link into the URL scheme its desktop app
/// registers (`zoommtg://`, `msteams://`, …), so Join opens the app directly
/// instead of a browser tab that then hands off to it.
///
/// Pure: it only builds the URL. Whether an app is installed to handle it is
/// the caller's check (`NSWorkspace.urlForApplication(toOpen:)`); without
/// one, the caller opens the original https link.
public enum NativeAppURL {

    public static func make(for url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http",
              let host = url.host()?.lowercased()
        else { return nil }

        if matches(host, ["zoom.us", "zoom.com", "zoomgov.com"]) { return zoom(url) }
        if matches(host, ["teams.microsoft.com", "teams.live.com"]) { return replacingScheme(url, "msteams") }
        if matches(host, ["slack.com"]) { return slackHuddle(url) }
        if matches(host, ["meet.jit.si"]) { return replacingScheme(url, "jitsi-meet") }
        return nil
    }

    private static func matches(_ host: String, _ suffixes: [String]) -> Bool {
        suffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// `https://acme.zoom.us/j/123?pwd=x` → `zoommtg://acme.zoom.us/join?action=join&confno=123&pwd=x`.
    /// Only `/j/<number>` links convert: personal rooms (`/my/name`) and
    /// other pages can't be opened through `zoommtg://`.
    private static func zoom(_ url: URL) -> URL? {
        let parts = url.pathComponents   // ["/", "j", "123"]
        guard parts.count == 3, parts[1] == "j",
              !parts[2].isEmpty, parts[2].allSatisfy(\.isNumber),
              let original = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        var app = URLComponents()
        app.scheme = "zoommtg"
        app.host = original.host
        app.path = "/join"
        app.queryItems = [
            URLQueryItem(name: "action", value: "join"),
            URLQueryItem(name: "confno", value: parts[2]),
        ] + (original.queryItems ?? [])
        return app.url
    }

    /// `https://app.slack.com/huddle/T123/C456` → `slack://join-huddle?team=T123&id=C456`.
    private static func slackHuddle(_ url: URL) -> URL? {
        let parts = url.pathComponents   // ["/", "huddle", "T123", "C456"]
        guard parts.count >= 4, parts[1] == "huddle",
              !parts[2].isEmpty, !parts[3].isEmpty
        else { return nil }

        var app = URLComponents()
        app.scheme = "slack"
        app.host = "join-huddle"
        app.queryItems = [
            URLQueryItem(name: "team", value: parts[2]),
            URLQueryItem(name: "id", value: parts[3]),
        ]
        return app.url
    }

    /// Same host, path and query; only the scheme changes.
    private static func replacingScheme(_ url: URL, _ scheme: String) -> URL? {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        c.scheme = scheme
        return c.url
    }
}
