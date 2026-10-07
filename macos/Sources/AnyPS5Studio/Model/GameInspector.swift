import Foundation

enum ExecutableKind: Equatable {
    case elf
    case selfContainer
    case tooSmall
    case unknown(String)

    var isConvertible: Bool { self == .elf }

    var label: String {
        switch self {
        case .elf: "Decrypted ELF"
        case .selfContainer: "Encrypted SELF"
        case .tooSmall: "Truncated file"
        case .unknown: "Not an ELF"
        }
    }

    var explanation: String {
        switch self {
        case .elf: "Ready for conversion."
        case .selfContainer: "SELF containers are encrypted. The relinker needs a clean, decrypted ELF."
        case .tooSmall: "The file is smaller than an ELF header."
        case .unknown(let magic): "Unrecognised magic bytes \(magic). Pick the game's decrypted eboot.bin."
        }
    }
}

struct ModuleDirectory: Identifiable, Equatable {
    let name: String
    let elfCount: Int
    var id: String { name }
}

struct GameInspection: Equatable {
    let executable: URL
    let kind: ExecutableKind
    let byteCount: Int64
    let moduleDirectories: [ModuleDirectory]
    let moduleIssue: String?
    let title: String?
    let titleId: String?
    let iconURL: URL?

    var root: URL { executable.deletingLastPathComponent() }

    var displayTitle: String { title ?? executable.deletingPathExtension().lastPathComponent }

    var moduleCount: Int { moduleDirectories.reduce(0) { $0 + $1.elfCount } }

    var blockingIssue: String? {
        if !kind.isConvertible { return kind.explanation }
        return moduleIssue
    }

    var suggestedOutputName: String {
        let base = titleId ?? executable.deletingPathExtension().lastPathComponent
        let cleaned = base.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return cleaned.isEmpty ? "app" : cleaned
    }
}

enum GameInspector {
    static let executableCandidates = ["eboot.bin", "eboot.elf"]

    static func resolveExecutable(from url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        guard isDirectory.boolValue else { return url }
        for name in executableCandidates {
            let candidate = url.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    static func inspect(_ executable: URL) -> GameInspection {
        let root = executable.deletingLastPathComponent()
        let attributes = try? FileManager.default.attributesOfItem(atPath: executable.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.int64Value ?? 0

        let (directories, issue) = moduleDirectories(in: root)
        let (title, titleId) = readParamJson(root.appendingPathComponent("sce_sys/param.json"))
        let icon = root.appendingPathComponent("sce_sys/icon0.png")

        return GameInspection(
            executable: executable,
            kind: classify(executable),
            byteCount: byteCount,
            moduleDirectories: directories,
            moduleIssue: issue,
            title: title,
            titleId: titleId,
            iconURL: FileManager.default.fileExists(atPath: icon.path) ? icon : nil
        )
    }

    static func classify(_ url: URL) -> ExecutableKind {
        guard let magic = readMagic(url) else { return .tooSmall }
        if magic == [0x7F, 0x45, 0x4C, 0x46] { return .elf }
        if magic == [0x4F, 0x15, 0x3D, 0x1D] { return .selfContainer }
        return .unknown(magic.map { String(format: "%02x", $0) }.joined(separator: " "))
    }

    private static func readMagic(_ url: URL) -> [UInt8]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return nil }
        return Array(data)
    }

    private static func moduleDirectories(in root: URL) -> ([ModuleDirectory], String?) {
        let manager = FileManager.default
        func exists(_ name: String) -> Bool { manager.fileExists(atPath: root.appendingPathComponent(name).path) }

        let hasSingular = exists("sce_module")
        let hasPlural = exists("sce_modules")
        let hasPrx = exists("prx")
        if hasSingular && hasPlural {
            return ([], "Both sce_module and sce_modules exist beside the executable. Keep only one.")
        }
        if !hasSingular && !hasPlural && !hasPrx {
            return ([], "No sce_module, sce_modules or prx folder was found beside the executable.")
        }

        var names: [String] = []
        if hasSingular { names.append("sce_module") }
        if hasPlural { names.append("sce_modules") }
        if hasPrx { names.append("prx") }

        var result: [ModuleDirectory] = []
        for name in names {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            _ = manager.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            guard isDirectory.boolValue else {
                return (result, "\(name) exists but is not a folder.")
            }
            let entries = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
            let elfCount = entries.filter { entry in
                (try? entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && classify(entry) == .elf
            }.count
            result.append(ModuleDirectory(name: name, elfCount: elfCount))
        }
        return (result, nil)
    }

    private static func readParamJson(_ url: URL) -> (String?, String?) {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, nil) }
        let titleId = root["titleId"] as? String
        guard let localized = root["localizedParameters"] as? [String: Any] else { return (nil, titleId) }
        let language = (localized["defaultLanguage"] as? String) ?? (root["defaultLanguage"] as? String)
        let entry = (language.flatMap { localized[$0] } as? [String: Any])
            ?? (localized["en-US"] as? [String: Any])
            ?? localized.values.compactMap { $0 as? [String: Any] }.first
        return (entry?["titleName"] as? String, titleId)
    }
}
