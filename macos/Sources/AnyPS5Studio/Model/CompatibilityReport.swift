import Foundation

struct CompatibilityReport {
    var entry: LibraryEntry
    var mac: String
    var macOS: String
    var runtime: String?
    var appVersion: String
    var crash: CrashSummary? = nil
    var home: String = NSHomeDirectory()

    var markdown: String {
        var rows: [(String, String)] = [
            ("Status", entry.status?.title ?? "Not set"),
            ("Target", entry.target.title),
            ("Mac", mac),
            ("macOS", macOS),
        ]
        if let runtime { rows.append(("Runtime", runtime)) }
        rows.append(("Relinker", entry.relinkerCommit.map { String($0.prefix(8)) } ?? "unknown"))
        rows.append(("AnyPS5 Studio", appVersion))
        let sessions = entry.sessions ?? []
        if let last = sessions.last {
            rows.append(("Play time", "\(PlayActivity.format(entry.playTime)) over \(sessions.count == 1 ? "1 session" : "\(sessions.count) sessions")"))
            rows.append(("Last exit code", "\(last.exitCode)"))
            if last.exitCode != 0, let crash, !crash.findings.isEmpty {
                rows.append(("Likely cause", Self.redact(crash.findings.map(\.headline).joined(separator: "; "), home: home)))
            }
        }
        var lines = ["### \(Self.cell(entry.title))" + (entry.titleId.map { " (\(Self.cell($0)))" } ?? ""), "", "| | |", "|---|---|"]
        lines += rows.map { "| \(Self.cell($0.0)) | \(Self.cell($0.1)) |" }
        if let notes = entry.notes, !notes.isEmpty {
            lines += ["", "Notes:", ""]
            lines += notes.components(separatedBy: .newlines).map { $0.isEmpty ? ">" : "> " + $0 }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func redact(_ text: String, home: String) -> String {
        guard home.count > 1 else { return text }
        let wine = "Z:" + home.replacingOccurrences(of: "/", with: "\\")
        return text
            .replacingOccurrences(of: wine, with: "~", options: .caseInsensitive)
            .replacingOccurrences(of: home, with: "~")
    }

    static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").components(separatedBy: .newlines).joined(separator: " ")
    }
}
