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
         freeBytes: Int64?, fileManager: FileManager = .default) {
        var checks: [PreflightCheck] = []
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: output.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        checks.append(PreflightCheck(
            id: "executable", title: "Executable",
            level: exists ? .ok : .failure,
            detail: exists ? output.lastPathComponent : "\(output.path) is missing. Convert the title again."))

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
        self.checks = checks
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
