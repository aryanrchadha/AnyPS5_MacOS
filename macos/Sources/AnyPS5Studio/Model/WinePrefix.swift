import Foundation

enum WinePrefix {
    static let folderName = "wine-prefix"

    static func folder(besides executable: URL) -> URL {
        executable.deletingLastPathComponent().appendingPathComponent(folderName, isDirectory: true)
    }

    static func exists(besides executable: URL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: folder(besides: executable).path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func apply(to global: [String: String], separate: Bool, executable: URL) -> [String: String] {
        guard separate else { return global }
        var result = global
        result["WINEPREFIX"] = folder(besides: executable).path
        return result
    }

    static func winetricksCommand(verb: String, environment: [String: String], wine: URL?) -> String {
        var parts: [String] = []
        if let prefix = environment["WINEPREFIX"] { parts.append("WINEPREFIX=" + LauncherBuilder.shellQuoted(prefix)) }
        if let wine { parts.append("WINE=" + LauncherBuilder.shellQuoted(wine.path)) }
        return (parts + ["winetricks", verb]).joined(separator: " ")
    }
}
