import Foundation
import XCTest
@testable import AnyPS5Studio

final class DiagnosticsReportTests: XCTestCase {
    func testTitleSectionListsProfileAndFrameRate() {
        var entry = makeEntry("Game", sessions: [
            PlaySession(start: Date(timeIntervalSince1970: 0), duration: 600, exitCode: 0,
                        averageFPS: 58.4, lowestFPS: 41, frameSize: FrameRateMeter.Size(width: 3840, height: 2160)),
            PlaySession(start: Date(timeIntervalSince1970: 3600), duration: 12, exitCode: -9),
        ])
        entry.profile = LaunchProfile(metalHUD: true, extraEnvironment: "ANYPS5_GPU=1", quietWine: true,
                                      wineRuntimePath: "/opt/wine", measureFrameRate: true)
        let lines = DiagnosticsReport(appVersion: "1.0", system: [], entry: entry, log: []).text
            .split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains("Launch profile: Metal HUD, Quiet Wine, Measure frame rate"))
        XCTAssertTrue(lines.contains("Wine runtime: /opt/wine"))
        XCTAssertEqual(lines.filter { $0.hasPrefix("Environment: ") }, [
            "Environment: ANYPS5_GPU=1",
            "Environment: APS5_PROFILE_DRAW=1",
            "Environment: MTL_HUD_ENABLED=1",
            "Environment: WINEDEBUG=-all",
        ])
        XCTAssertTrue(lines.contains("Session: 1970-01-01T00:00:00Z 600s exit 0, 58 fps average, 41 lowest at 3840 \u{D7} 2160"))
        XCTAssertTrue(lines.contains("Session: 1970-01-01T01:00:00Z 12s exit -9"))
    }

    func testDefaultProfile() {
        let text = DiagnosticsReport(appVersion: "1.0", system: [], entry: makeEntry("Game"), log: []).text
        XCTAssertTrue(text.contains("Launch profile: default\n"))
        XCTAssertFalse(text.contains("Environment: "))
        XCTAssertFalse(text.contains("Wine runtime: "))
    }
}
