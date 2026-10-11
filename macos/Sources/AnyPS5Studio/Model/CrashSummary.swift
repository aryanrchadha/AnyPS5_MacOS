import Foundation

struct CrashFinding: Equatable {
    enum Kind: String {
        case missingFunction
        case exception
        case fault
        case missingLibrary
        case gpu
    }

    let kind: Kind
    let headline: String
    let detail: String?
}

struct CrashSummary: Equatable {
    static let limit = 5
    static let tailBytes = 512 * 1024

    let findings: [CrashFinding]

    var headline: String? { findings.first?.headline }

    static let faultNames: [String: String] = [
        "C0000005": "access violation",
        "C000001D": "illegal instruction",
        "C0000096": "privileged instruction",
        "C00000FD": "stack overflow",
        "C0000094": "integer division by zero",
        "C0000409": "stack buffer overrun",
        "80000003": "breakpoint",
    ]

    static let markers = ["what()", "[coredump]", "terminate called", "[libc] unhandled", "FATAL:", "wine: Unhandled", ") not found", "Vulkan: no usable"]

    init(findings: [CrashFinding]) {
        self.findings = findings
    }

    init(lines: [String]) {
        var findings: [CrashFinding] = []
        var seen = Set<String>()
        func add(_ finding: CrashFinding) {
            guard findings.count < Self.limit, seen.insert(finding.headline).inserted else { return }
            findings.append(finding)
        }
        let cleaned = lines.map(Self.strip)
        for (index, line) in cleaned.enumerated() where Self.markers.contains(where: { line.contains($0) }) {
            let next = index + 1 < cleaned.count ? cleaned[index + 1] : ""
            if let what = Self.capture(#"what\(\):\s*(.+?) not implemented\s*$"#, in: line) {
                add(CrashFinding(kind: .missingFunction, headline: "Missing function: \(what)",
                                 detail: "The game called a system function the runtime does not implement yet."))
            } else if let groups = Self.captures(#"\[coredump\] uncaught C\+\+ exception \S+ of type (.+?), what\(\): (.+)$"#, in: line) {
                add(CrashFinding(kind: .exception, headline: "Uncaught \(groups[0]): \(groups[1])", detail: nil))
            } else if let type = Self.capture(#"\[coredump\] uncaught C\+\+ exception \S+ of type (.+)$"#, in: line) {
                add(CrashFinding(kind: .exception, headline: "Uncaught \(type)", detail: nil))
            } else if let type = Self.capture(#"terminate called after throwing an instance of '(.+)'"#, in: line) {
                if let what = Self.capture(#"^\s*what\(\):\s*(.+)$"#, in: next) {
                    if what.hasSuffix(" not implemented") { continue }
                    add(CrashFinding(kind: .exception, headline: "Uncaught \(type): \(what)", detail: nil))
                } else {
                    add(CrashFinding(kind: .exception, headline: "Uncaught \(type)", detail: nil))
                }
            } else if let type = Self.capture(#"\[libc\] unhandled exception '(.+?)'"#, in: line) {
                add(CrashFinding(kind: .exception, headline: "Uncaught \(type)", detail: nil))
            } else if let groups = Self.captures(#"FATAL: unhandled exception 0x([0-9A-Fa-f]{8}) on thread (\d+) '(.*)'"#, in: line) {
                let code = groups[0].uppercased()
                let name = Self.faultNames[code].map { " (\($0))" } ?? ""
                let thread = groups[2].isEmpty ? "thread \(groups[1])" : "thread \(groups[1]) \u{2018}\(groups[2])\u{2019}"
                let rip = Self.capture(#"^\s*rip (.+)$"#, in: next)
                add(CrashFinding(kind: .fault, headline: "Fault 0x\(code)\(name) on \(thread)", detail: rip.map { "at \($0)" }))
            } else if let what = Self.capture(#"^wine: Unhandled (.+)$"#, in: line) {
                add(CrashFinding(kind: .fault, headline: "Wine: unhandled \(what)", detail: nil))
            } else if let groups = Self.captures(#"Library (\S+) \(which is needed by (.+?)\) not found"#, in: line) {
                add(CrashFinding(kind: .missingLibrary, headline: "Missing library: \(groups[0])",
                                 detail: "Needed by \(groups[1]). The Wine runtime does not provide it."))
            } else if line.contains("Vulkan: no usable device") {
                add(CrashFinding(kind: .gpu, headline: "No usable Vulkan device", detail: line))
            }
        }
        self.findings = findings
    }

    init(text: String) {
        self.init(lines: text.components(separatedBy: .newlines))
    }

    static func read(log url: URL) -> CrashSummary? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        return CrashSummary(text: String(decoding: data, as: UTF8.self))
    }

    private static func strip(_ line: String) -> String {
        line.hasPrefix("! ") || line.hasPrefix("# ") ? String(line.dropFirst(2)) : line
    }

    private static func capture(_ pattern: String, in line: String) -> String? {
        captures(pattern, in: line)?.first
    }

    private static func captures(_ pattern: String, in line: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: line).map { String(line[$0]) } ?? ""
        }
    }
}
