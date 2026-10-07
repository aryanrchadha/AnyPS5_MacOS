import Foundation
import Observation

struct LogLine: Identifiable, Equatable {
    enum Source { case stdout, stderr, system }

    let id: Int
    let text: String
    let source: Source

    enum Tone { case plain, success, warning, failure, muted, accent }

    var tone: Tone {
        if source == .system { return .accent }
        if text.hasPrefix("FAIL") || text.localizedCaseInsensitiveContains("error") { return .failure }
        if text.hasPrefix("WARNING") || text.hasPrefix("Intel substitution") { return .warning }
        if text.hasPrefix("OK") || text.localizedCaseInsensitiveContains("success") { return .success }
        return source == .stderr ? .warning : .plain
    }
}

@Observable
final class ProcessRunner {
    enum State: Equatable {
        case idle
        case running(label: String, started: Date)
        case finished(label: String, exitCode: Int32, duration: TimeInterval)
        case failedToStart(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    private static let lineLimit = 25_000

    private(set) var lines: [LogLine] = []
    private(set) var state: State = .idle

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var nextLineID = 0
    @ObservationIgnored private let ioQueue = DispatchQueue(label: "anyps5.studio.process-io")
    @ObservationIgnored private var pending: [LogLine.Source: Data] = [:]

    func clear() {
        guard !state.isRunning else { return }
        lines.removeAll()
        state = .idle
    }

    func note(_ text: String) {
        append([(text, .system)])
    }

    func run(label: String, executable: URL, arguments: [String], workingDirectory: URL?,
             environment: [String: String] = [:], completion: ((Int32) -> Void)? = nil) {
        guard !state.isRunning else { return }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardInput = FileHandle.nullDevice

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        attach(stdout, as: .stdout)
        attach(stderr, as: .stderr)

        let started = Date()
        process.terminationHandler = { [weak self] finished in
            guard let self else { return }
            self.ioQueue.async {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                self.consume(stdout.fileHandleForReading.readDataToEndOfFile(), from: .stdout)
                self.consume(stderr.fileHandleForReading.readDataToEndOfFile(), from: .stderr)
                self.flushPending()
                let code = finished.terminationStatus
                DispatchQueue.main.async {
                    self.process = nil
                    self.state = .finished(label: label, exitCode: code, duration: Date().timeIntervalSince(started))
                    completion?(code)
                }
            }
        }

        note("$ " + ([executable.path] + arguments).shellCommand)
        do {
            try process.run()
            self.process = process
            state = .running(label: label, started: started)
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            state = .failedToStart(error.localizedDescription)
            note("Could not start \(executable.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func terminate() {
        process?.terminate()
    }

    private func attach(_ pipe: Pipe, as source: LogLine.Source) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self.ioQueue.async { self.consume(data, from: source) }
        }
    }

    private func consume(_ data: Data, from source: LogLine.Source) {
        guard !data.isEmpty else { return }
        var buffer = pending[source, default: Data()]
        buffer.append(data)
        var complete: [(String, LogLine.Source)] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            let text = String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            complete.append((text, source))
        }
        pending[source] = buffer
        if !complete.isEmpty { DispatchQueue.main.async { self.append(complete) } }
    }

    private func flushPending() {
        var rest: [(String, LogLine.Source)] = []
        for source in [LogLine.Source.stdout, .stderr] {
            if let data = pending[source], !data.isEmpty {
                rest.append((String(decoding: data, as: UTF8.self), source))
            }
        }
        pending.removeAll()
        if !rest.isEmpty { DispatchQueue.main.async { self.append(rest) } }
    }

    private func append(_ entries: [(String, LogLine.Source)]) {
        for (text, source) in entries {
            lines.append(LogLine(id: nextLineID, text: text, source: source))
            nextLineID += 1
        }
        if lines.count > Self.lineLimit {
            lines.removeFirst(lines.count - Self.lineLimit)
        }
    }
}
