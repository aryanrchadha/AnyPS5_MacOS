import Foundation

enum PreflightLevel: Int, Comparable {
    case ok
    case warning
    case failure

    static func < (lhs: PreflightLevel, rhs: PreflightLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct PreflightCheck: Identifiable, Equatable {
    let id: String
    let title: String
    let level: PreflightLevel
    let detail: String
}

enum PowerState: Equatable {
    case normal
    case lowPower
    case hot(critical: Bool)

    var detail: String? {
        switch self {
        case .normal:
            return nil
        case .lowPower:
            return "Low Power Mode is on, which lowers CPU and GPU clocks. Turn it off in System Settings \u{203A} Battery for full performance."
        case .hot(let critical):
            return critical
                ? "This Mac is critically hot and macOS is throttling it hard. Let it cool before playing."
                : "This Mac is hot and macOS is throttling the CPU and GPU. Frame rates will be lower until it cools."
        }
    }
}

extension PowerState {
    static let fullPerformance = "Low Power Mode is off and macOS reports no thermal throttling."

    static func summary(_ states: [PowerState]) -> String {
        let details = states.compactMap(\.detail)
        return details.isEmpty ? fullPerformance : details.joined(separator: " ")
    }
}

struct LaunchPreflight: Equatable {
    static let minimumFreeBytes: Int64 = 2 * 1024 * 1024 * 1024

    let checks: [PreflightCheck]

    var level: PreflightLevel { checks.map(\.level).max() ?? .ok }
    var canLaunch: Bool { level < .failure }
    var failures: [PreflightCheck] { checks.filter { $0.level == .failure } }
    var warnings: [PreflightCheck] { checks.filter { $0.level == .warning } }

    var summary: String {
        switch level {
        case .ok: return "Ready to launch"
        case .warning: return warnings.count == 1 ? "Ready, with 1 warning" : "Ready, with \(warnings.count) warnings"
        case .failure: return failures.count == 1 ? "1 problem blocks launch" : "\(failures.count) problems block launch"
        }
    }

    init(checks: [PreflightCheck]) {
        self.checks = checks
    }

    init(output: URL, runtime: URL?, runtimeName: String?, pinnedRuntime: String?, needsRosetta: Bool,
         freeBytes: Int64?, displays: [DisplayTarget] = [], power: [PowerState] = [],
         fileManager: FileManager = .default) {
        var checks = [Self.executableCheck(output, fileManager: fileManager)]

        if let runtime {
            let name = runtimeName ?? runtime.lastPathComponent
            if !fileManager.isExecutableFile(atPath: runtime.path) {
                checks.append(PreflightCheck(id: "runtime", title: "Wine runtime", level: .failure,
                                             detail: "\(runtime.path) is not executable. Reinstall \(name)."))
            } else if let pinnedRuntime, pinnedRuntime != runtime.path {
                checks.append(PreflightCheck(id: "runtime", title: "Wine runtime", level: .warning,
                                             detail: "\(pinnedRuntime) is not installed; \(name) is used instead."))
            } else {
                checks.append(PreflightCheck(id: "runtime", title: "Wine runtime", level: .ok, detail: name))
            }
        } else {
            checks.append(PreflightCheck(id: "runtime", title: "Wine runtime", level: .failure,
                                         detail: "No Wine runtime is installed. Install CrossOver, Whisky or Wine."))
        }

        if needsRosetta {
            checks.append(PreflightCheck(id: "rosetta", title: "Rosetta 2", level: .failure,
                                         detail: "Wine runs x86-64 code through Rosetta 2. Run: softwareupdate --install-rosetta --agree-to-license"))
        }

        self.checks = checks + Self.hostChecks(output: output, executableExists: checks[0].level == .ok,
                                               freeBytes: freeBytes, displays: displays, power: power,
                                               fileManager: fileManager)
    }

    init(nativeOutput output: URL, libraries: URL?, needsRosetta: Bool, freeBytes: Int64?,
         displays: [DisplayTarget] = [], power: [PowerState] = [], fileManager: FileManager = .default) {
        var checks = [Self.executableCheck(output, fileManager: fileManager)]

        if let libraries {
            let kernel = libraries.appendingPathComponent(Self.nativeKernel)
            let found = fileManager.fileExists(atPath: kernel.path)
            checks.append(PreflightCheck(
                id: "libraries", title: "macOS system libraries",
                level: found ? .ok : .failure,
                detail: found ? "\(Self.nativeKernel) in \(libraries.lastPathComponent)/"
                              : "\(kernel.path) is missing. Import AnyPS5's system libraries built for macOS: the macos-libs-x86_64 artifact of the macOS system libraries workflow, or a build on a Mac."))
        } else {
            checks.append(PreflightCheck(
                id: "libraries", title: "macOS system libraries", level: .warning,
                detail: "The library search path is not under the output folder, so it is not checked."))
        }

        if needsRosetta {
            checks.append(PreflightCheck(id: "rosetta", title: "Rosetta 2", level: .failure,
                                         detail: "macOS output is x86-64 code that runs through Rosetta 2. Run: softwareupdate --install-rosetta --agree-to-license"))
        }

        self.checks = checks + Self.hostChecks(output: output, executableExists: checks[0].level == .ok,
                                               freeBytes: freeBytes, displays: displays, power: power,
                                               fileManager: fileManager)
    }

    static let nativeKernel = "libkernel.prx"

    static func markExecutable(_ output: URL, fileManager: FileManager = .default) throws {
        let current = (try fileManager.attributesOfItem(atPath: output.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
        guard current & 0o111 != 0o111 else { return }
        try fileManager.setAttributes([.posixPermissions: current | 0o111], ofItemAtPath: output.path)
    }

    private static func executableCheck(_ output: URL, fileManager: FileManager) -> PreflightCheck {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: output.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        return PreflightCheck(
            id: "executable", title: "Executable",
            level: exists ? .ok : .failure,
            detail: exists ? output.lastPathComponent : "\(output.path) is missing. Convert the title again.")
    }

    private static func hostChecks(output: URL, executableExists exists: Bool, freeBytes: Int64?,
                                   displays: [DisplayTarget], power: [PowerState],
                                   fileManager: FileManager) -> [PreflightCheck] {
        var checks: [PreflightCheck] = []
        let folder = output.deletingLastPathComponent()
        if exists {
            let writable = fileManager.isWritableFile(atPath: folder.path)
            checks.append(PreflightCheck(
                id: "folder", title: "Output folder",
                level: writable ? .ok : .failure,
                detail: writable ? "Saves and the shader cache can be written"
                                 : "\(folder.path) is read-only, so saves and the shader cache cannot be written."))
        }

        if let freeBytes {
            let free = ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)
            let low = freeBytes < Self.minimumFreeBytes
            checks.append(PreflightCheck(
                id: "disk", title: "Free space",
                level: low ? .warning : .ok,
                detail: low ? "Only \(free) free. Saves and the shader cache may fail to write." : "\(free) free"))
        }
        let powerDetails = power.compactMap(\.detail)
        if !powerDetails.isEmpty {
            checks.append(PreflightCheck(id: "power", title: "Performance", level: .warning,
                                         detail: powerDetails.joined(separator: " ")))
        }
        let advice = displays.compactMap(\.refreshAdvice)
        if !advice.isEmpty {
            checks.append(PreflightCheck(id: "display", title: "Display refresh rate", level: .warning,
                                         detail: advice.joined(separator: " ")))
        }
        return checks
    }

    static func freeBytes(near url: URL, fileManager: FileManager = .default) -> Int64? {
        var candidate = url
        while !fileManager.fileExists(atPath: candidate.path), candidate.pathComponents.count > 1 {
            candidate.deleteLastPathComponent()
        }
        guard let attributes = try? fileManager.attributesOfFileSystem(forPath: candidate.path),
              let free = attributes[.systemFreeSize] as? NSNumber else { return nil }
        return free.int64Value
    }
}
