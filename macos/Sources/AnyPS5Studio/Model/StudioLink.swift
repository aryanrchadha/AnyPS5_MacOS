import Foundation

enum StudioLink: Equatable {
    static let scheme = "anyps5"

    static let pages = ["convert", "library", "controls", "console", "system"]

    case launch(String)
    case page(String)

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let action = (components.host ?? "").lowercased()
        let path = components.path.split(separator: "/").map(String.init)
        let query = components.queryItems?.first { $0.name.lowercased() == "title" }?.value
        let target = (path.first ?? query)?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case _ where Self.pages.contains(action) && target == nil:
            self = .page(action)
        case "launch":
            guard let target, !target.isEmpty else { return nil }
            self = .launch(target)
        default:
            return nil
        }
    }

    static func identifier(for entry: LibraryEntry) -> String {
        entry.titleId ?? entry.title
    }

    static func launchURL(for entry: LibraryEntry) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "launch"
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let value = identifier(for: entry).addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        components.percentEncodedQuery = "title=" + value
        return components.url
    }

    static func match(_ target: String, in entries: [LibraryEntry]) -> LibraryEntry? {
        let candidates = entries.sorted { LibraryOrganizer.lastActivity($0) > LibraryOrganizer.lastActivity($1) }
        return candidates.first { $0.titleId?.caseInsensitiveCompare(target) == .orderedSame }
            ?? candidates.first { $0.title.caseInsensitiveCompare(target) == .orderedSame }
    }
}
