import Foundation

struct SessionRow: Equatable, Identifiable {
    let id: Int
    let start: Date
    let duration: String
    let exitCode: Int32
    let frameRate: String?
    let meetsTarget: Bool

    var succeeded: Bool { exitCode == 0 }
}

enum SessionHistory {
    static let limit = 5

    static func rows(for entry: LibraryEntry, limit: Int = limit) -> [SessionRow] {
        let sessions = entry.sessions ?? []
        return sessions.indices.suffix(limit).reversed().map { index in
            let session = sessions[index]
            return SessionRow(id: index, start: session.start, duration: PlayActivity.format(session.duration),
                              exitCode: session.exitCode,
                              frameRate: session.averageFPS.map { FrameRateMeter.chipText(average: $0, size: session.frameSize) },
                              meetsTarget: session.averageFPS.map { FrameRateMeter.meetsTarget(average: $0, size: session.frameSize) } ?? false)
        }
    }

    static func frameRateChange(for entry: LibraryEntry) -> String? {
        let measured = (entry.sessions ?? []).filter { $0.averageFPS != nil }
        guard measured.count >= 2, let latest = measured.last?.averageFPS,
              let previous = measured[measured.count - 2].averageFPS else { return nil }
        let delta = Int((latest - previous).rounded())
        let change = delta == 0 ? "Same average as" : "\(delta > 0 ? "+" : "\u{2212}")\(abs(delta)) fps from"
        let reference = "the previous measurement (\(Int(previous.rounded())) fps)"
        let sizes = (measured.last?.frameSize, measured[measured.count - 2].frameSize)
        guard let latestSize = sizes.0, let previousSize = sizes.1, latestSize != previousSize else {
            return "\(change) \(reference)"
        }
        return "\(change) \(reference), which ran at \(previousSize.text) instead of \(latestSize.text)"
    }

    static let csvHeader = "start,duration_seconds,exit_code,average_fps,lowest_fps,width,height"

    static func csv(for entry: LibraryEntry) -> String {
        let iso = ISO8601DateFormatter()
        let rows = (entry.sessions ?? []).map { session in
            [iso.string(from: session.start),
             String(Int(session.duration.rounded())),
             String(session.exitCode),
             session.averageFPS.map { String(format: "%.1f", $0) } ?? "",
             session.lowestFPS.map { String(format: "%.1f", $0) } ?? "",
             session.frameSize.map { String($0.width) } ?? "",
             session.frameSize.map { String($0.height) } ?? ""].joined(separator: ",")
        }
        return ([csvHeader] + rows).joined(separator: "\n") + "\n"
    }
}
