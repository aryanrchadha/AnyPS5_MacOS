import Foundation

enum SessionLog {
    static let retention = 10
    static let prefix = "Session"

    static var root: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return library.appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("AnyPS5 Studio", isDirectory: true)
    }

    static func folder(title: String, titleId: String?, root: URL = root) -> URL {
        root.appendingPathComponent(LauncherBuilder.bundleName(for: titleId.map { "\(title) (\($0))" } ?? title), isDirectory: true)
    }

    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date)).log"
    }

    static func text(_ lines: [LogLine], title: String, started: Date, duration: TimeInterval, exitCode: Int32) -> String {
        var output = [
            "# \(title)",
            "# Started: \(ISO8601DateFormatter().string(from: started))",
            "# Duration: \(Int(duration))s",
            "# Exit code: \(exitCode)",
            ""
        ]
        for line in lines {
            switch line.source {
            case .system: output.append("# " + line.text)
            case .stderr: output.append("! " + line.text)
            case .stdout: output.append(line.text)
            }
        }
        return output.joined(separator: "\n") + "\n"
    }

    static func logs(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "log" && $0.lastPathComponent.hasPrefix(prefix + " ") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func expired(_ logs: [URL], keeping count: Int = retention) -> [URL] {
        Array(logs.sorted { $0.lastPathComponent > $1.lastPathComponent }.dropFirst(max(count, 0)))
    }
}
