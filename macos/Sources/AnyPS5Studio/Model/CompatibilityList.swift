import Foundation

struct CompatibilityRecord: Equatable {
    let game: String
    let titleId: String
    let results: [(platform: String, status: String)]

    static func == (lhs: CompatibilityRecord, rhs: CompatibilityRecord) -> Bool {
        lhs.game == rhs.game && lhs.titleId == rhs.titleId
            && lhs.results.map(\.platform) == rhs.results.map(\.platform)
            && lhs.results.map(\.status) == rhs.results.map(\.status)
    }

    var summary: String {
        let known = results.filter { $0.status != "?" && !$0.status.isEmpty }
        guard !known.isEmpty else { return "Listed, no results yet" }
        return known.map { "\($0.platform): \($0.status)" }.joined(separator: " · ")
    }
}

struct CompatibilityList {
    private(set) var records: [String: CompatibilityRecord] = [:]

    init(markdown: String) {
        var header: [String]?
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|") else {
                header = nil
                continue
            }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst().dropLast()
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" } }) { continue }
            guard let columns = header else {
                header = cells
                continue
            }
            guard let idIndex = columns.firstIndex(where: { $0.caseInsensitiveCompare("ID") == .orderedSame }),
                  idIndex < cells.count else { continue }
            let gameIndex = columns.firstIndex(where: { $0.caseInsensitiveCompare("Game") == .orderedSame }) ?? 0
            let titleId = cells[idIndex].uppercased()
            guard !titleId.isEmpty else { continue }
            let results = zip(columns, cells).enumerated()
                .filter { $0.offset != idIndex && $0.offset != gameIndex }
                .map { (platform: $0.element.0, status: $0.element.1) }
            records[titleId] = CompatibilityRecord(
                game: gameIndex < cells.count ? cells[gameIndex] : titleId,
                titleId: titleId,
                results: results
            )
        }
    }

    func record(for titleId: String?) -> CompatibilityRecord? {
        guard let titleId else { return nil }
        return records[titleId.uppercased()]
    }

    static func load() -> CompatibilityList? {
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "COMPATIBILITY", withExtension: "md") {
            candidates.append(bundled)
        }
        var directory = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<6 {
            guard let current = directory else { break }
            candidates.append(current.appendingPathComponent("docs/user/COMPATIBILITY.md"))
            directory = current.deletingLastPathComponent()
        }
        for url in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return CompatibilityList(markdown: text)
            }
        }
        return nil
    }
}
