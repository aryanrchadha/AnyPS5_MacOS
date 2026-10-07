import Foundation

enum TargetPlatform: String, CaseIterable, Identifiable, Codable {
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

enum UnusedFilter: Int, CaseIterable, Identifiable, Codable {
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

struct ConversionSettings: Equatable, Codable {
    static let defaultRunPath = "$ORIGIN/libs"

    var target: TargetPlatform = .windows
    var toIntel = true
    var unusedFilter: UnusedFilter = .keepAll
    var writeRegistry = false
    var runPath = ConversionSettings.defaultRunPath
    var windowsGUI = true
    var windowsDiagnostics = false

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
    var shellCommand: String {
        map { argument in
            let safe = argument.allSatisfy { $0.isLetter || $0.isNumber || "-_./=:+,@".contains($0) }
            return safe ? argument : "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        .joined(separator: " ")
    }
}
