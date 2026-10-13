import Foundation
import XCTest
@testable import AnyPS5Studio

final class FrameRateMeterTests: XCTestCase {
    private func flip(_ resident: Int, notPending: Int = 0, unsuitable: Int = 0) -> String {
        "! [flip] \(resident) presents from the resident image (3 refreshed first), through guest memory: \(notPending) not pending, \(unsuitable) unsuitable; 0 GPU frame dumps"
    }

    func testParsesFlipAndSwapchainLines() {
        XCTAssertEqual(FrameRateMeter.presents(in: flip(1000, notPending: 20, unsuitable: 5)), 1025)
        XCTAssertNil(FrameRateMeter.presents(in: "[flip] something else"))
        XCTAssertNil(FrameRateMeter.presents(in: "1000 presents from the resident image"))
        XCTAssertEqual(FrameRateMeter.size(in: "[VulkanDevice.cpp:1130 present] Swapchain created swapchain=0x7f extent=3840x2160 images=3"),
                       FrameRateMeter.Size(width: 3840, height: 2160))
        XCTAssertNil(FrameRateMeter.size(in: "Resize complete swapchain=0x7f extent=3840x2160 images=3"))
        XCTAssertNil(FrameRateMeter.size(in: "Swapchain created extent=0x2160"))
    }

    func testRatesBetweenReports() {
        var meter = FrameRateMeter()
        let start = Date(timeIntervalSince1970: 1_000)
        meter.ingest("Swapchain created swapchain=0x1 extent=3840x2160 images=3", at: start)
        XCTAssertNil(meter.ingest(flip(600), at: start))
        XCTAssertEqual(meter.ingest(flip(1800), at: start.addingTimeInterval(10)), 120)
        XCTAssertEqual(meter.ingest(flip(2400, notPending: 10), at: start.addingTimeInterval(20)), 61)
        XCTAssertNil(meter.ingest(flip(2400, notPending: 10), at: start.addingTimeInterval(30)))
        XCTAssertNil(meter.ingest(flip(2500, notPending: 10), at: start.addingTimeInterval(30.5)))
        XCTAssertEqual(meter.rates, [120, 61])
        XCTAssertEqual(meter.average, 90.5)
        XCTAssertEqual(meter.lowest, 61)
        XCTAssertEqual(meter.size?.isUHD, true)
        XCTAssertEqual(meter.summary, "91 fps average, 61 lowest at 3840 \u{D7} 2160")
    }

    func testCounterResetDoesNotProduceARate() {
        var meter = FrameRateMeter()
        let start = Date(timeIntervalSince1970: 0)
        meter.ingest(flip(5000), at: start)
        XCTAssertNil(meter.ingest(flip(100), at: start.addingTimeInterval(10)))
        XCTAssertEqual(meter.ingest(flip(700), at: start.addingTimeInterval(20)), 60)
        XCTAssertEqual(FrameRateMeter().summary, nil)
        XCTAssertFalse(FrameRateMeter.Size(width: 2560, height: 1440).isUHD)
    }

    func testSessionDecodesWithoutFrameRate() throws {
        let old = try JSONDecoder().decode(PlaySession.self, from: Data(#"{"start":0,"duration":60,"exitCode":0}"#.utf8))
        XCTAssertNil(old.averageFPS)
        XCTAssertNil(old.frameSize)
        let profile = LaunchProfile(measureFrameRate: true)
        XCTAssertEqual(profile.environment[FrameRateMeter.environmentKey], "1")
        XCTAssertNil(LaunchProfile().environment[FrameRateMeter.environmentKey])
    }

    func testTargetAndReportRow() {
        let uhd = FrameRateMeter.Size(width: 3840, height: 2160)
        XCTAssertTrue(FrameRateMeter.meetsTarget(average: 119.6, size: uhd))
        XCTAssertFalse(FrameRateMeter.meetsTarget(average: 100, size: uhd))
        XCTAssertFalse(FrameRateMeter.meetsTarget(average: 120, size: FrameRateMeter.Size(width: 2560, height: 1440)))
        XCTAssertFalse(FrameRateMeter.meetsTarget(average: 120, size: nil))
        let entry = makeEntry("Game", sessions: [
            PlaySession(start: Date(timeIntervalSince1970: 0), duration: 600, exitCode: 0, averageFPS: 58.4, lowestFPS: 41, frameSize: uhd),
            PlaySession(start: Date(timeIntervalSince1970: 1000), duration: 60, exitCode: 0),
        ])
        let report = CompatibilityReport(entry: entry, mac: "M", macOS: "m", runtime: nil, appVersion: "1").markdown
        XCTAssertTrue(report.contains("| Frame rate | 58 fps average, 41 lowest at 3840 \u{D7} 2160 |"), report)
        XCTAssertFalse(CompatibilityReport(entry: makeEntry("Game", sessions: [PlaySession(start: Date(), duration: 1, exitCode: 0)]),
                                           mac: "M", macOS: "m", runtime: nil, appVersion: "1").markdown.contains("Frame rate"))
    }

    func testChipTextAndLastMeasuredSession() {
        XCTAssertEqual(FrameRateMeter.chipText(average: 119.7, size: FrameRateMeter.Size(width: 3840, height: 2160)), "120 fps \u{B7} 4K")
        XCTAssertEqual(FrameRateMeter.chipText(average: 59.6, size: FrameRateMeter.Size(width: 2560, height: 1440)), "60 fps \u{B7} 1440p")
        XCTAssertEqual(FrameRateMeter.chipText(average: 30, size: nil), "30 fps")
        let entry = makeEntry("Game", sessions: [
            PlaySession(start: Date(timeIntervalSince1970: 0), duration: 60, exitCode: 0, averageFPS: 45, lowestFPS: 30),
            PlaySession(start: Date(timeIntervalSince1970: 100), duration: 60, exitCode: 0, averageFPS: 58, lowestFPS: 50),
            PlaySession(start: Date(timeIntervalSince1970: 200), duration: 60, exitCode: 0),
        ])
        XCTAssertEqual(entry.lastMeasuredSession?.averageFPS, 58)
        XCTAssertNil(makeEntry("New").lastMeasuredSession)
    }

    func testRefreshCap() {
        let studio = DisplayTarget(name: "Studio Display", pixelWidth: 5120, pixelHeight: 2880, maximumRefreshRate: 60)
        let tv = DisplayTarget(name: "TV", pixelWidth: 3840, pixelHeight: 2160, maximumRefreshRate: 60, bestRefreshRate: 120)
        let promotion = DisplayTarget(name: "Built-in", pixelWidth: 3456, pixelHeight: 2234, maximumRefreshRate: 120)
        XCTAssertEqual(FrameRateMeter.refreshCap(average: 59.2, displays: [promotion, studio])?.name, "Studio Display")
        XCTAssertNil(FrameRateMeter.refreshCap(average: 45, displays: [studio]))
        XCTAssertNil(FrameRateMeter.refreshCap(average: 119, displays: [promotion]))
        XCTAssertNil(FrameRateMeter.refreshCap(average: 60, displays: [DisplayTarget(name: "Unknown", pixelWidth: 1, pixelHeight: 1, maximumRefreshRate: 0)]))
        let fixed = FrameRateMeter.refreshAdvice(average: 60.4, displays: [studio])
        XCTAssertEqual(fixed, "The average matches the 60 Hz refresh rate of Studio Display. Frames are presented with vsync, so this display caps the frame rate at 60 FPS; the title may also pace itself at that rate. A higher frame rate needs a display that refreshes at 120 Hz.")
        let switchable = FrameRateMeter.refreshAdvice(average: 58, displays: [tv])
        XCTAssertTrue(switchable?.hasSuffix("Choose 120 Hz under Refresh rate in System Settings \u{203A} Displays and measure again.") == true)
        XCTAssertNil(FrameRateMeter.refreshAdvice(average: 30, displays: [tv]))
    }
}
