import Darwin
import Foundation

struct WineRuntime: Identifiable, Equatable, Hashable {
    let name: String
    let executable: URL
    var id: String { executable.path }
}

struct SystemReport: Equatable {
    var chip: String
    var isAppleSilicon: Bool
    var isTranslated: Bool
    var macOSVersion: OperatingSystemVersion
    var memoryBytes: UInt64
    var rosettaInstalled: Bool
    var wineRuntimes: [WineRuntime]

    var macOSLabel: String {
        "macOS \(macOSVersion.majorVersion).\(macOSVersion.minorVersion)"
            + (macOSVersion.patchVersion > 0 ? ".\(macOSVersion.patchVersion)" : "")
    }

    var memoryLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }

    var rosettaHasAVX2: Bool { macOSVersion.majorVersion >= 15 }

    static func == (lhs: SystemReport, rhs: SystemReport) -> Bool {
        lhs.chip == rhs.chip && lhs.isAppleSilicon == rhs.isAppleSilicon && lhs.isTranslated == rhs.isTranslated
            && lhs.macOSVersion.majorVersion == rhs.macOSVersion.majorVersion
            && lhs.macOSVersion.minorVersion == rhs.macOSVersion.minorVersion
            && lhs.macOSVersion.patchVersion == rhs.macOSVersion.patchVersion
            && lhs.memoryBytes == rhs.memoryBytes && lhs.rosettaInstalled == rhs.rosettaInstalled
            && lhs.wineRuntimes == rhs.wineRuntimes
    }
}

enum SystemProbe {
    static func report() -> SystemReport {
        SystemReport(
            chip: sysctlString("machdep.cpu.brand_string") ?? "Unknown processor",
            isAppleSilicon: sysctlInt("hw.optional.arm64") == 1,
            isTranslated: sysctlInt("sysctl.proc_translated") == 1,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersion,
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            rosettaInstalled: FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime"),
            wineRuntimes: wineRuntimes()
        )
    }

    static func wineRuntimes() -> [WineRuntime] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates: [(String, String)] = [
            ("CrossOver", "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"),
            ("Whisky", home + "/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64"),
            ("Game Porting Toolkit", "/usr/local/opt/game-porting-toolkit/bin/wine64"),
            ("Wine (Homebrew)", "/opt/homebrew/bin/wine64"),
            ("Wine (Homebrew)", "/opt/homebrew/bin/wine"),
            ("Wine", "/usr/local/bin/wine64"),
            ("Wine", "/usr/local/bin/wine"),
        ]
        var seen = Set<String>()
        return candidates.compactMap { name, path in
            guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            guard seen.insert(resolved.path).inserted else { return nil }
            return WineRuntime(name: name, executable: URL(fileURLWithPath: path))
        }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}

enum RelinkerLocator {
    static let overrideKey = "relinkerPathOverride"

    static func locate() -> URL? {
        let manager = FileManager.default
        if let override = UserDefaults.standard.string(forKey: overrideKey), !override.isEmpty,
           manager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "relinker"),
           manager.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        var candidates: [String] = []
        var directory = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<6 {
            guard let current = directory else { break }
            candidates.append(current.appendingPathComponent("build-macos/relinker/core/relinker/relinker").path)
            candidates.append(current.appendingPathComponent("build/core/relinker/relinker").path)
            directory = current.deletingLastPathComponent()
        }
        candidates += ["/opt/homebrew/bin/relinker", "/usr/local/bin/relinker"]
        return candidates.first(where: manager.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }
}
