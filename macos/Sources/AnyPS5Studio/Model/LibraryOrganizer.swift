import Foundation

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent, title, playTime, size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Recent"
        case .title: "Title"
        case .playTime: "Play time"
        case .size: "Size"
        }
    }
}

enum LibraryStatusFilter: Hashable, Identifiable {
    case all
    case notSet
    case status(PlayStatus)

    static var allCases: [LibraryStatusFilter] { [.all, .notSet] + PlayStatus.allCases.map { .status($0) } }

    var id: String {
        switch self {
        case .all: "all"
        case .notSet: "notSet"
        case .status(let status): status.rawValue
        }
    }

    var title: String {
        switch self {
        case .all: "All statuses"
        case .notSet: "Status not set"
        case .status(let status): status.title
        }
    }

    func matches(_ entry: LibraryEntry) -> Bool {
        switch self {
        case .all: true
        case .notSet: entry.status == nil
        case .status(let status): entry.status == status
        }
    }
}

enum LibraryOrganizer {
    static func arrange(_ entries: [LibraryEntry], query: String, sort: LibrarySort,
                        favorites: Set<String>, sizes: [String: Int64] = [:],
                        status: LibraryStatusFilter = .all) -> [LibraryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matching = entries.filter(status.matches)
        let filtered = trimmed.isEmpty ? matching : matching.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) || ($0.titleId ?? "").localizedCaseInsensitiveContains(trimmed)
                || ($0.notes ?? "").localizedCaseInsensitiveContains(trimmed)
                || ($0.status?.title ?? "").localizedCaseInsensitiveContains(trimmed)
        }
        let sorted: [LibraryEntry]
        switch sort {
        case .recent:
            sorted = filtered.sorted { lastActivity($0) > lastActivity($1) }
        case .title:
            sorted = filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .playTime:
            sorted = filtered.sorted { $0.playTime > $1.playTime }
        case .size:
            sorted = filtered.sorted { (sizes[key($0)] ?? 0) > (sizes[key($1)] ?? 0) }
        }
        let pinned = sorted.filter { favorites.contains(key($0)) }
        let rest = sorted.filter { !favorites.contains(key($0)) }
        return pinned + rest
    }

    static func key(_ entry: LibraryEntry) -> String {
        entry.output.standardizedFileURL.path
    }

    static func lastActivity(_ entry: LibraryEntry) -> Date {
        max(entry.convertedAt, entry.lastSession.map { $0.start.addingTimeInterval($0.duration) } ?? .distantPast)
    }

    static func folderSize(_ directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [], errorHandler: nil) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}

struct DiagnosticsReport {
    var appVersion: String
    var system: [(String, String)]
    var entry: LibraryEntry?
    var log: [String]

    var text: String {
        var lines = ["AnyPS5 Studio diagnostics", "Generated: \(ISO8601DateFormatter().string(from: Date()))", "App version: \(appVersion)", ""]
        lines.append("[System]")
        lines += system.map { "\($0.0): \($0.1)" }
        if let entry {
            lines += ["", "[Title]",
                      "Title: \(entry.title)",
                      "Title ID: \(entry.titleId ?? "unknown")",
                      "Target: \(entry.target.title)",
                      "Output: \(entry.output.path)",
                      "Converted: \(ISO8601DateFormatter().string(from: entry.convertedAt))",
                      "Exit code: \(entry.exitCode)",
                      "Status: \(entry.status?.title ?? "not set")"]
            if let notes = entry.notes { lines += notes.split(separator: "\n", omittingEmptySubsequences: false).map { "Notes: \($0)" } }
            if let report = entry.report {
                lines.append("Guest modules: \(report.guestModules)")
                if let external = report.externalReferences { lines.append("System imports: \(external)") }
                if let before = report.nidBefore, let after = report.nidAfter { lines.append("NID references: \(before) -> \(after)") }
                if let total = report.intelTotal { lines.append("AMD-only rewrites: \(total)") }
                if let failure = report.failure { lines.append("Failure: \(failure)") }
            }
            for session in (entry.sessions ?? []).suffix(10) {
                lines.append("Session: \(ISO8601DateFormatter().string(from: session.start)) \(Int(session.duration))s exit \(session.exitCode)")
            }
        }
        lines += ["", "[Console]"]
        lines += log.suffix(2_000)
        return lines.joined(separator: "\n") + "\n"
    }
}
