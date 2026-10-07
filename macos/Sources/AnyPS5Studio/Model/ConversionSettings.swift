import Foundation

/// Output format the relinker writes. Mirrors `--windows` in docs/user/USAGE.md.
enum TargetPlatform: String, CaseIterable, Identifiable {
    case windows
    case linux

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windows: "Windows PE"
        case .linux: "Linux ELF"
        }
    }

    var fileExtension: String {
        switch self {
        case .windows: "exe"
        case .linux: "elf"
        }
    }

    var summary: String {
        switch self {
        case .windows: "Runs on this Mac through Wine, CrossOver or Whisky. Experimental."
        case .linux: "Runs on a Linux x86-64 machine or VM. Cannot start natively on macOS."
        }
    }

    var symbol: String {
        switch self {
        case .windows: "macwindow.on.rectangle"
        case .linux: "terminal"
        }
    }
}

/// `unused-filter=0|1|2`.
enum UnusedFilter: Int, CaseIterable, Identifiable {
    case keepAll = 0
    case filter = 1
    case strict = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .keepAll: "Keep all"
        case .filter: "Filter"
        case .strict: "Strict"
        }
    }

    var detail: String {
        switch self {
        case .keepAll: "Keep every imported NID reference."
        case .filter: "Drop unused non-PLT imports using control-flow and GOT analysis."
        case .strict: "Strict analysis and PLT compaction. Unsupported cases fail the conversion."
        }
    }
}

struct ConversionSettings: Equatable {
    static let defaultRunPath = "$ORIGIN/libs"

    var target: TargetPlatform = .windows
    /// Apple Silicon runs x86-64 code through Rosetta 2, which implements Intel's
    /// instruction set. AMD-only instructions (SSE4a, CLZERO, ...) must be lowered.
    var toIntel = true
    var unusedFilter: UnusedFilter = .keepAll
    var writeRegistry = false
    var runPath = ConversionSettings.defaultRunPath
    var windowsGUI = true
    var windowsDiagnostics = false

    /// Problems that would make the relinker reject the arguments (exit code 1).
    var validationIssue: String? {
        let trimmed = runPath.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "The library search path cannot be empty." }
        switch target {
        case .windows:
            if !trimmed.allSatisfy(\.isASCII) { return "Windows library search paths must be ASCII." }
        case .linux:
            if !trimmed.hasPrefix("/") && !trimmed.hasPrefix("$ORIGIN") {
                return "Linux search paths must be absolute or start with $ORIGIN."
            }
        }
        return nil
    }

    func arguments(input: URL, output: URL) -> [String] {
        var arguments: [String] = []
        if target == .windows {
            arguments.append("--windows")
            if windowsGUI { arguments.append("--windows-gui") }
            if windowsDiagnostics { arguments.append("--windows-diagnostics") }
        }
        if toIntel { arguments.append("--to-intel") }
        if unusedFilter != .keepAll { arguments.append("unused-filter=\(unusedFilter.rawValue)") }
        if writeRegistry { arguments.append("--registry") }
        let trimmed = runPath.trimmingCharacters(in: .whitespaces)
        if trimmed != Self.defaultRunPath {
            arguments.append(contentsOf: ["--rpath", trimmed])
        }
        arguments.append(input.path)
        arguments.append(output.path)
        return arguments
    }

    /// Directory the runtime searches for system `.prx` libraries, when it can be resolved
    /// relative to the output executable.
    func libraryDirectory(besides executable: URL) -> URL? {
        let trimmed = runPath.trimmingCharacters(in: .whitespaces)
        let base = executable.deletingLastPathComponent()
        if trimmed == "$ORIGIN" { return base }
        if trimmed.hasPrefix("$ORIGIN/") {
            return base.appendingPathComponent(String(trimmed.dropFirst("$ORIGIN/".count)), isDirectory: true)
        }
        if trimmed.hasPrefix("/") { return URL(fileURLWithPath: trimmed, isDirectory: true) }
        return nil
    }
}

extension Array where Element == String {
    /// Shell-quoted rendering for the command preview.
    var shellCommand: String {
        map { argument in
            let safe = argument.allSatisfy { $0.isLetter || $0.isNumber || "-_./=:+,@".contains($0) }
            return safe ? argument : "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        .joined(separator: " ")
    }
}
