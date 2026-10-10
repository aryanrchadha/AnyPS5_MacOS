import Foundation

struct StorageReport: Equatable {
    var titles: Int64 = 0
    var shaderCaches: Int64 = 0
    var saves: Int64 = 0
    var saveBackups: Int64 = 0
    var sessionLogs: Int64 = 0
    var titleCount = 0

    static func measure(outputs: [URL], backupRoot: URL, logRoot: URL) -> StorageReport {
        var report = StorageReport()
        var seen = Set<String>()
        for output in outputs {
            let folder = output.deletingLastPathComponent().standardizedFileURL
            guard FileManager.default.fileExists(atPath: folder.path), seen.insert(folder.path).inserted else { continue }
            report.titleCount += 1
            report.titles += LibraryOrganizer.folderSize(folder)
            report.shaderCaches += LibraryOrganizer.folderSize(folder.appendingPathComponent("shader_cache", isDirectory: true))
            report.saves += LibraryOrganizer.folderSize(folder.appendingPathComponent(SaveData.folderName, isDirectory: true))
        }
        report.saveBackups = LibraryOrganizer.folderSize(backupRoot)
        report.sessionLogs = LibraryOrganizer.folderSize(logRoot)
        return report
    }
}
