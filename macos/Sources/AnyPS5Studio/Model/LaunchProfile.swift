import Foundation

struct LaunchProfile: Codable, Equatable {
    var metalHUD = false
    var disableShaderCache = false
    var extraEnvironment = ""
    var backupSavesOnLaunch = false
    var quietWine = false
    var wineRuntimePath: String?

    init(metalHUD: Bool = false, disableShaderCache: Bool = false, extraEnvironment: String = "",
         backupSavesOnLaunch: Bool = false, quietWine: Bool = false, wineRuntimePath: String? = nil) {
        self.metalHUD = metalHUD
        self.disableShaderCache = disableShaderCache
        self.extraEnvironment = extraEnvironment
        self.backupSavesOnLaunch = backupSavesOnLaunch
        self.quietWine = quietWine
        self.wineRuntimePath = wineRuntimePath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metalHUD = try container.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? false
        disableShaderCache = try container.decodeIfPresent(Bool.self, forKey: .disableShaderCache) ?? false
        extraEnvironment = try container.decodeIfPresent(String.self, forKey: .extraEnvironment) ?? ""
        backupSavesOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .backupSavesOnLaunch) ?? false
        quietWine = try container.decodeIfPresent(Bool.self, forKey: .quietWine) ?? false
        wineRuntimePath = try container.decodeIfPresent(String.self, forKey: .wineRuntimePath)
    }

    var environment: [String: String] {
        var result: [String: String] = quietWine ? ["WINEDEBUG": "-all"] : [:]
        result.merge(EnvironmentText.parse(extraEnvironment)) { _, explicit in explicit }
        if metalHUD { result["MTL_HUD_ENABLED"] = "1" }
        if disableShaderCache { result["ANYPS5_NO_SHADER_CACHE"] = "1" }
        return result
    }

    func merged(over base: [String: String]) -> [String: String] {
        base.merging(environment) { _, profile in profile }
    }

    static let diagnosticWineDebug = "fixme-all"

    static func diagnostic(_ environment: [String: String]) -> [String: String] {
        var result = environment
        result["WINEDEBUG"] = diagnosticWineDebug
        return result
    }
}

struct PlaySession: Codable, Equatable {
    var start: Date
    var duration: TimeInterval
    var exitCode: Int32
}

enum EnvironmentText {
    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { continue }
            result[key] = String(trimmed[trimmed.index(after: separator)...])
        }
        return result
    }
}

enum ShaderCache {
    static func directory(besides executable: URL) -> URL {
        executable.deletingLastPathComponent().appendingPathComponent("shader_cache", isDirectory: true)
    }

    static func size(at directory: URL) -> (files: Int, bytes: Int64) {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return (0, 0) }
        var files = 0
        var bytes: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            files += 1
            bytes += Int64(values.fileSize ?? 0)
        }
        return (files, bytes)
    }

    static func clear(at directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}

struct DisplayTarget: Equatable {
    var name: String
    var pixelWidth: Int
    var pixelHeight: Int
    var maximumRefreshRate: Int

    var supports4K: Bool { max(pixelWidth, pixelHeight) >= 3840 && min(pixelWidth, pixelHeight) >= 2160 }
    var supports120Hz: Bool { maximumRefreshRate >= 120 }
}
