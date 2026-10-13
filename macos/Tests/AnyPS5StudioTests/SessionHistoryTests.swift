import Foundation
import XCTest
@testable import AnyPS5Studio

final class SessionHistoryTests: XCTestCase {
    func testNewestFirstWithinTheLimit() {
        let uhd = FrameRateMeter.Size(width: 3840, height: 2160)
        var sessions: [PlaySession] = (0..<7).map { index in
            PlaySession(start: Date(timeIntervalSince1970: Double(index) * 1000), duration: Double(index + 1) * 600, exitCode: 0)
        }
        sessions[5].exitCode = 3
        sessions[4].averageFPS = 58
        sessions[4].lowestFPS = 40
        sessions[4].frameSize = uhd
        sessions[6].averageFPS = 119.5
        sessions[6].lowestFPS = 40
        sessions[6].frameSize = uhd
        let rows: [SessionRow] = SessionHistory.rows(for: makeEntry("Game", sessions: sessions))
        XCTAssertEqual(rows.map { $0.id }, [6, 5, 4, 3, 2])
        XCTAssertEqual(rows[0].duration, "1h 10m")
        XCTAssertEqual(rows[0].frameRate, "120 fps \u{B7} 4K")
        XCTAssertTrue(rows[0].meetsTarget)
        XCTAssertFalse(rows[1].succeeded)
        XCTAssertNil(rows[1].frameRate)
        XCTAssertEqual(rows[2].frameRate, "58 fps \u{B7} 4K")
        XCTAssertFalse(rows[2].meetsTarget)
        XCTAssertEqual(SessionHistory.rows(for: makeEntry("Game", sessions: sessions), limit: 2).map { $0.id }, [6, 5])
        XCTAssertTrue(SessionHistory.rows(for: makeEntry("New")).isEmpty)
    }

    func testCSV() {
        let entry = makeEntry("Game", sessions: [
            PlaySession(start: Date(timeIntervalSince1970: 0), duration: 600.4, exitCode: 0,
                        averageFPS: 58.44, lowestFPS: 41, frameSize: FrameRateMeter.Size(width: 3840, height: 2160)),
            PlaySession(start: Date(timeIntervalSince1970: 3600), duration: 12, exitCode: -9),
        ])
        XCTAssertEqual(SessionHistory.csv(for: entry), """
        start,duration_seconds,exit_code,average_fps,lowest_fps,width,height
        1970-01-01T00:00:00Z,600,0,58.4,41.0,3840,2160
        1970-01-01T01:00:00Z,12,-9,,,,

        """)
        XCTAssertEqual(SessionHistory.csv(for: makeEntry("New")), SessionHistory.csvHeader + "\n")
    }

    func testFrameRateChange() {
        let uhd = FrameRateMeter.Size(width: 3840, height: 2160)
        let qhd = FrameRateMeter.Size(width: 2560, height: 1440)
        func session(_ average: Double?, _ size: FrameRateMeter.Size? = nil) -> PlaySession {
            PlaySession(start: Date(timeIntervalSince1970: 0), duration: 60, exitCode: 0,
                        averageFPS: average, lowestFPS: average.map { $0 - 10 }, frameSize: size)
        }
        XCTAssertNil(SessionHistory.frameRateChange(for: makeEntry("New")))
        XCTAssertNil(SessionHistory.frameRateChange(for: makeEntry("One", sessions: [session(60, uhd), session(nil)])))
        XCTAssertEqual(SessionHistory.frameRateChange(for: makeEntry("Up", sessions: [session(48.2, uhd), session(nil), session(60.4, uhd)])),
                       "+12 fps from the previous measurement (48 fps)")
        XCTAssertEqual(SessionHistory.frameRateChange(for: makeEntry("Down", sessions: [session(60, uhd), session(55, uhd)])),
                       "\u{2212}5 fps from the previous measurement (60 fps)")
        XCTAssertEqual(SessionHistory.frameRateChange(for: makeEntry("Same", sessions: [session(59.8), session(60.1)])),
                       "Same average as the previous measurement (60 fps)")
        XCTAssertEqual(SessionHistory.frameRateChange(for: makeEntry("Resized", sessions: [session(90, qhd), session(60, uhd)])),
                       "\u{2212}30 fps from the previous measurement (90 fps), which ran at 2560 \u{D7} 1440 instead of 3840 \u{D7} 2160")
    }
}
