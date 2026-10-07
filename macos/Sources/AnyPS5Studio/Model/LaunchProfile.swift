import Foundation

struct LaunchProfile: Codable, Equatable {
    var metalHUD = false
    var disableShaderCache = false
    var extraEnvironment = ""

    var environment: [String: String] {
        var result = EnvironmentText.parse(extraEnvironment)
        if metalHUD { result["MTL_HUD_ENABLED"] = "1" }
        if disableShaderCache { result["ANYPS5_NO_SHADER_CACHE"] = "1" }
        return result
    }

    func merged(over base: [String: String]) -> [String: String] {
        base.merging(environment) { _, profile in profile }
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
