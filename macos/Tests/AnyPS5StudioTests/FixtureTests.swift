import Foundation
import XCTest
@testable import AnyPS5Studio

final class FixtureTests: XCTestCase {
    func testSampleLibraryDecodes() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/library.json")
        let entries = try LibraryArchive.decoder.decode([LibraryEntry].self, from: Data(contentsOf: url))
        XCTAssertEqual(entries.map(\.titleId), ["PPSA00001", "PPSA00002", "PPSA00003", "PPSA00004", nil])
        XCTAssertEqual(entries[0].status, .playable)
        XCTAssertEqual(entries.map(\.publisher), [.electronicArts, nil, nil, nil, nil])
        XCTAssertEqual(entries[0].sessions?.count, 2)
        XCTAssertEqual(entries[0].lastMeasuredSession?.frameRateText, "58 fps average, 41 lowest at 3840 \u{D7} 2160")
        XCTAssertEqual(entries[1].lastSession?.exitCode, 3)
        XCTAssertEqual(entries[2].target, .linux)
        XCTAssertFalse(entries[3].succeeded)
        XCTAssertEqual(entries[0].output.path, "/tmp/anyps5-fixture/Long/eboot.exe")
        XCTAssertTrue(entries.allSatisfy { $0.output.path.hasPrefix("/tmp/anyps5-fixture/") })
    }
}
