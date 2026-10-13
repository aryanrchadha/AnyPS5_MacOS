import Foundation

enum SharedFonts {
    static let folderName = "anyps5-fonts"
    static let extensions: Set<String> = ["otf", "ttf", "ttc"]

    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AnyPS5 Studio/Fonts", isDirectory: true)
    }

    enum Source: Equatable {
        case own(Int)
        case linked(Int)
        case none
    }

    static func localFolder(besides executable: URL) -> URL {
        executable.deletingLastPathComponent().appendingPathComponent(folderName, isDirectory: true)
    }

    static func fonts(in folder: URL, fileManager: FileManager = .default) -> [URL] {
        ((try? fileManager.contentsOfDirectory(at: folder.resolvingSymlinksInPath(), includingPropertiesForKeys: nil)) ?? [])
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func collect(from urls: [URL], fileManager: FileManager = .default) -> [URL] {
        var result: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                result += fonts(in: url, fileManager: fileManager)
            } else if extensions.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result
    }

    static func copy(_ fonts: [URL], to destination: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for font in fonts {
            let target = destination.appendingPathComponent(font.lastPathComponent)
            guard font.standardizedFileURL.path != target.standardizedFileURL.path else { continue }
            if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
            try fileManager.copyItem(at: font, to: target)
        }
    }

    static func isLink(_ url: URL, fileManager: FileManager = .default) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    static func source(besides executable: URL, fileManager: FileManager = .default) -> Source {
        let local = localFolder(besides: executable)
        let count = fonts(in: local, fileManager: fileManager).count
        if isLink(local, fileManager: fileManager) { return count > 0 ? .linked(count) : .none }
        return count > 0 ? .own(count) : .none
    }

    static func isShared(besides executable: URL, shared: URL = defaultFolder, fileManager: FileManager = .default) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: localFolder(besides: executable).path)) == shared.path
    }

    static func detachShared(besides executable: URL, shared: URL = defaultFolder, fileManager: FileManager = .default) throws {
        let local = localFolder(besides: executable)
        guard isLink(local, fileManager: fileManager) else { return }
        if isShared(besides: executable, shared: shared, fileManager: fileManager) || !fileManager.fileExists(atPath: local.path) {
            try fileManager.removeItem(at: local)
        }
    }

    @discardableResult
    static func link(besides executable: URL, shared: URL = defaultFolder, fileManager: FileManager = .default) throws -> Bool {
        let local = localFolder(besides: executable)
        guard !fonts(in: shared, fileManager: fileManager).isEmpty else { return false }
        if isLink(local, fileManager: fileManager) {
            let destination = try fileManager.destinationOfSymbolicLink(atPath: local.path)
            if destination == shared.path || !fonts(in: local, fileManager: fileManager).isEmpty { return false }
            try fileManager.removeItem(at: local)
        } else if fileManager.fileExists(atPath: local.path) {
            return false
        }
        try fileManager.createSymbolicLink(atPath: local.path, withDestinationPath: shared.path)
        return true
    }
}
