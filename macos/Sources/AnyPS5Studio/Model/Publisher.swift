import Foundation

struct ContentID: Equatable {
    let raw: String
    let serviceId: String
    let titleId: String

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.range(of: #"^[A-Z]{2}[0-9]{4}-[A-Z]{4}[0-9]{5}_[0-9]{2}-[A-Z0-9]{1,16}$"#, options: .regularExpression) != nil else { return nil }
        self.raw = trimmed
        serviceId = String(trimmed.prefix(6))
        titleId = String(trimmed.dropFirst(7).prefix(9))
    }

    var publisher: Publisher? { Publisher.serviceIds[serviceId] }
}

enum Publisher: String, CaseIterable, Identifiable {
    case electronicArts

    static let serviceIds: [String: Publisher] = ["UP0006": .electronicArts, "EP0006": .electronicArts]

    var id: String { rawValue }

    var name: String {
        switch self {
        case .electronicArts: "Electronic Arts"
        }
    }

    var shortName: String {
        switch self {
        case .electronicArts: "EA"
        }
    }

    var notes: [PublisherNote] {
        switch self {
        case .electronicArts:
            [PublisherNote(title: "Online modes",
                           detail: "EA titles reach EA's servers through PlayStation Network. The runtime answers most network checks as signed out, and some network functions are not implemented yet: a title that calls one stops with a \"not implemented\" error naming it. Ultimate Team, online seasons, co-op, EA account linking and other online modes are unavailable; play the offline modes."),
             PublisherNote(title: "Rosters and live content",
                           detail: "Roster updates, live tuning and content a title downloads while running are not fetched. The title uses only what is in the dumped game folder, so include its installed updates when you dump it."),
             PublisherNote(title: "Frame rate",
                           detail: "A title cannot run faster than its PS5 version targets. If the title offers a 120 Hz or performance mode in its own video settings, choose it; otherwise expect at most 60 FPS. Turn on Measure frame rate to check.")]
        }
    }
}

struct PublisherNote: Equatable, Hashable {
    let title: String
    let detail: String
}

struct ParamJson: Equatable {
    var title: String?
    var titleId: String?
    var contentId: String?

    init(title: String? = nil, titleId: String? = nil, contentId: String? = nil) {
        self.title = title
        self.titleId = titleId
        self.contentId = contentId
    }

    init(data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        titleId = root["titleId"] as? String
        contentId = root["contentId"] as? String
        guard let localized = root["localizedParameters"] as? [String: Any] else { return }
        let language = (localized["defaultLanguage"] as? String) ?? (root["defaultLanguage"] as? String)
        let entry = (language.flatMap { localized[$0] } as? [String: Any])
            ?? (localized["en-US"] as? [String: Any])
            ?? localized.values.compactMap { $0 as? [String: Any] }.first
        title = entry?["titleName"] as? String
    }

    static func read(besides executable: URL) -> ParamJson {
        let url = executable.deletingLastPathComponent().appendingPathComponent("sce_sys/param.json")
        guard let data = try? Data(contentsOf: url) else { return ParamJson() }
        return ParamJson(data: data)
    }
}

extension LibraryEntry {
    var publisher: Publisher? { contentId.flatMap(ContentID.init)?.publisher }
}
