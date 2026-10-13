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

enum StorageCleanup {
    static func clearShaderCaches(outputs: [URL]) -> (cleared: Int, failed: [String]) {
        var seen = Set<String>()
        var cleared = 0
        var failed: [String] = []
        for output in outputs {
            let cache = ShaderCache.directory(besides: output).standardizedFileURL
            guard seen.insert(cache.path).inserted, FileManager.default.fileExists(atPath: cache.path) else { continue }
            do {
                try ShaderCache.clear(at: cache)
                cleared += 1
            } catch {
                failed.append(cache.path)
            }
        }
        return (cleared, failed)
    }

    static func deleteSessionLogs(root: URL) -> Int {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        var deleted = 0
        for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            for log in SessionLog.logs(in: folder) where (try? manager.removeItem(at: log)) != nil {
                deleted += 1
            }
            if (try? manager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
                try? manager.removeItem(at: folder)
            }
        }
        return deleted
    }
}
