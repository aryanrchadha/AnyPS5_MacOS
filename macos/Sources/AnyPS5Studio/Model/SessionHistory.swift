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
}
