import Foundation
import XCTest
@testable import AnyPS5Studio

func temporaryDirectory(_ name: String = #function) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("AnyPS5StudioTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

func makeEntry(_ title: String, titleId: String? = nil, output: String? = nil, convertedAt: TimeInterval = 0,
               sessions: [PlaySession]? = nil, status: PlayStatus? = nil) -> LibraryEntry {
    var entry = LibraryEntry(title: title, titleId: titleId, source: URL(fileURLWithPath: "/source"),
                             output: URL(fileURLWithPath: output ?? "/output/\(title)/\(title).exe"),
                             target: .windows, convertedAt: Date(timeIntervalSince1970: convertedAt),
                             exitCode: 0, iconURL: nil)
    entry.sessions = sessions
    entry.status = status
    return entry
}
