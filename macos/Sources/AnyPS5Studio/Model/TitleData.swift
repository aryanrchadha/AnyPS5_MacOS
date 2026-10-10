import Foundation

struct EntitlementsFile: Equatable {
    static let fileName = "anyps5-entitlements.ini"
    static let maximumLabelLength = 15

    private(set) var labels: [String] = []
    private(set) var issues: [String] = []

    init() {}

    init(contents: String) {
        for (index, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
            var line = rawLine
            if let comment = line.firstIndex(where: { $0 == "#" || $0 == ";" }) { line = String(line[..<comment]) }
            let label = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r"))
            if label.isEmpty { continue }
            if let problem = Self.problem(with: label) {
                issues.append("Line \(index + 1): \(problem)")
                continue
            }
            if !labels.contains(label) { labels.append(label) }
        }
    }

    static func problem(with label: String) -> String? {
        if label.isEmpty { return "The label is empty." }
        if label.utf8.count > maximumLabelLength { return "'\(label)' is longer than \(maximumLabelLength) characters." }
        if label.contains(where: { $0 == "#" || $0 == ";" || $0.isNewline }) { return "'\(label)' contains a comment character." }
        return nil
    }

    mutating func add(_ label: String) throws {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if let problem = Self.problem(with: trimmed) { throw TitleDataError.invalid(problem) }
        if !labels.contains(trimmed) { labels.append(trimmed) }
    }

    mutating func remove(_ label: String) {
        labels.removeAll { $0 == label }
    }

    var serialized: String {
        labels.isEmpty ? "" : labels.joined(separator: "\n") + "\n"
    }
}

enum TitleDataError: Error, CustomStringConvertible {
    case invalid(String)
    case toolFailed(String)

    var description: String {
        switch self {
        case .invalid(let message): message
        case .toolFailed(let message): message
        }
    }
}

struct SaveBackup: Identifiable, Equatable {
    let url: URL
    let created: Date
    let bytes: Int64
    var id: String { url.path }
}

enum SaveData {
    static let folderName = "_sd"
    static let automaticPrefix = "Auto"
    static let automaticRetention = 5

    static func directory(besides executable: URL) -> URL {
        executable.deletingLastPathComponent().appendingPathComponent(folderName, isDirectory: true)
    }

    static let backupFolderKey = "saveBackupFolder"
    static let backupFolderName = "AnyPS5 Saves"

    static var defaultBackupRoot: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        return documents.appendingPathComponent(backupFolderName, isDirectory: true)
    }

    static var iCloudBackupRoot: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: drive.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return drive.appendingPathComponent(backupFolderName, isDirectory: true)
    }

    static func backupRoot(configured path: String?) -> URL {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), path.hasPrefix("/") else { return defaultBackupRoot }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    static var backupRoot: URL {
        backupRoot(configured: UserDefaults.standard.string(forKey: backupFolderKey))
    }

    static func backupFolder(title: String, titleId: String?, root: URL = backupRoot) -> URL {
        let base = LauncherBuilder.bundleName(for: titleId.map { "\(title) (\($0))" } ?? title)
        return root.appendingPathComponent(base, isDirectory: true)
    }

    static func backupName(for date: Date, automatic: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(automatic ? automaticPrefix : "Saves") \(formatter.string(from: date)).zip"
    }

    static func isAutomatic(_ backup: SaveBackup) -> Bool {
        backup.url.lastPathComponent.hasPrefix(automaticPrefix + " ")
    }

    static func expiredAutomaticBackups(in backups: [SaveBackup], keeping count: Int = automaticRetention) -> [SaveBackup] {
        Array(backups.filter(isAutomatic).sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }.dropFirst(max(count, 0)))
    }

    static func backups(in folder: URL) -> [SaveBackup] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "zip" }
            .map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return SaveBackup(url: url,
                                  created: values?.creationDate ?? values?.contentModificationDate ?? .distantPast,
                                  bytes: Int64(values?.fileSize ?? 0))
            }
            .sorted { $0.created > $1.created }
    }

    static func hasSaves(at directory: URL) -> Bool {
        ShaderCache.size(at: directory).files > 0
    }
}
