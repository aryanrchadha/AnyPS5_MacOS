import Foundation
import XCTest
@testable import AnyPS5Studio

final class LaunchPreflightTests: XCTestCase {
    private func makeRuntime(in folder: URL) throws -> URL {
        let wine = folder.appendingPathComponent("bin/wine64")
        try write("#!/bin/sh\n", to: wine)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        return wine
    }

    func testReadyTitle() throws {
        let folder = try temporaryDirectory()
        let output = folder.appendingPathComponent("Game/Game.exe")
        try write("MZ", to: output)
        let wine = try makeRuntime(in: folder)
        let check = LaunchPreflight(output: output, runtime: wine, runtimeName: "Wine", pinnedRuntime: wine.path,
                                    needsRosetta: false, freeBytes: 50 * 1024 * 1024 * 1024)
        XCTAssertEqual(check.checks.map(\.id), ["executable", "runtime", "folder", "disk"])
        XCTAssertEqual(check.level, .ok)
        XCTAssertTrue(check.canLaunch)
        XCTAssertEqual(check.summary, "Ready to launch")
    }

    func testMissingExecutableAndRuntimeBlockLaunch() throws {
        let folder = try temporaryDirectory()
        let output = folder.appendingPathComponent("Gone/Gone.exe")
        let check = LaunchPreflight(output: output, runtime: nil, runtimeName: nil, pinnedRuntime: nil,
                                    needsRosetta: true, freeBytes: nil)
        XCTAssertFalse(check.canLaunch)
        XCTAssertEqual(check.failures.map(\.id), ["executable", "runtime", "rosetta"])
        XCTAssertFalse(check.checks.contains { $0.id == "folder" || $0.id == "disk" })
        XCTAssertEqual(check.summary, "3 problems block launch")
    }

    func testNonExecutableRuntimeFails() throws {
        let folder = try temporaryDirectory()
        let output = folder.appendingPathComponent("Game/Game.exe")
        try write("MZ", to: output)
        let wine = folder.appendingPathComponent("wine")
        try write("text", to: wine)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: wine.path)
        let check = LaunchPreflight(output: output, runtime: wine, runtimeName: "Wine", pinnedRuntime: nil,
                                    needsRosetta: false, freeBytes: nil)
        XCTAssertEqual(check.failures.map(\.id), ["runtime"])
    }

    func testDirectoryIsNotAnExecutable() throws {
        let folder = try temporaryDirectory()
        let output = folder.appendingPathComponent("Game.exe", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let check = LaunchPreflight(output: output, runtime: try makeRuntime(in: folder), runtimeName: "Wine",
                                    pinnedRuntime: nil, needsRosetta: false, freeBytes: nil)
        XCTAssertEqual(check.failures.map(\.id), ["executable"])
    }

    func testMissingPinAndLowDiskWarn() throws {
        let folder = try temporaryDirectory()
        let output = folder.appendingPathComponent("Game/Game.exe")
        try write("MZ", to: output)
        let wine = try makeRuntime(in: folder)
        let check = LaunchPreflight(output: output, runtime: wine, runtimeName: "Wine", pinnedRuntime: "/Applications/Gone.app",
                                    needsRosetta: false, freeBytes: LaunchPreflight.minimumFreeBytes - 1)
        XCTAssertTrue(check.canLaunch)
        XCTAssertEqual(check.level, .warning)
        XCTAssertEqual(check.warnings.map(\.id), ["runtime", "disk"])
        XCTAssertTrue(check.warnings[0].detail.contains("/Applications/Gone.app"))
        XCTAssertEqual(check.summary, "Ready, with 2 warnings")
    }

    func testFreeBytesWalksUpToAnExistingFolder() throws {
        let folder = try temporaryDirectory()
        let free = LaunchPreflight.freeBytes(near: folder.appendingPathComponent("a/b/c.exe"))
        XCTAssertNotNil(free)
        XCTAssertGreaterThan(free ?? 0, 0)
    }

    func testDisplayBelowItsBestRefreshRateWarns() throws {
        let folder = try temporaryDirectory()
        let output = folder.appendingPathComponent("Game/Game.exe")
        try write("MZ", to: output)
        let wine = try makeRuntime(in: folder)
        let slow = DisplayTarget(name: "Studio Display XDR", pixelWidth: 3840, pixelHeight: 2160, maximumRefreshRate: 60, bestRefreshRate: 120)
        let fixed = DisplayTarget(name: "Office", pixelWidth: 2560, pixelHeight: 1440, maximumRefreshRate: 60, bestRefreshRate: 60)
        let fast = DisplayTarget(name: "Built-in", pixelWidth: 3456, pixelHeight: 2234, maximumRefreshRate: 120)
        XCTAssertNil(fixed.refreshAdvice)
        XCTAssertNil(fast.refreshAdvice)
        XCTAssertEqual(slow.availableRefreshRate, 120)
        XCTAssertTrue(slow.refreshAdvice?.hasPrefix("Studio Display XDR runs at 60 Hz but can run at 120 Hz.") ?? false)
        let check = LaunchPreflight(output: output, runtime: wine, runtimeName: "Wine", pinnedRuntime: nil, needsRosetta: false,
                                    freeBytes: nil, displays: [fast, slow, fixed])
        XCTAssertTrue(check.canLaunch)
        XCTAssertEqual(check.warnings.map(\.id), ["display"])
        XCTAssertEqual(LaunchPreflight(output: output, runtime: wine, runtimeName: "Wine", pinnedRuntime: nil, needsRosetta: false,
                                       freeBytes: nil, displays: [fast, fixed]).level, .ok)
    }

    func testLowPowerAndHeatWarn() throws {
        let folder = try temporaryDirectory()
        let output = folder.appendingPathComponent("Game/Game.exe")
        try write("MZ", to: output)
        let wine = try makeRuntime(in: folder)
        func check(_ power: [PowerState]) -> LaunchPreflight {
            LaunchPreflight(output: output, runtime: wine, runtimeName: "Wine", pinnedRuntime: nil, needsRosetta: false,
                            freeBytes: nil, power: power)
        }
        XCTAssertEqual(check([]).level, .ok)
        XCTAssertEqual(check([.normal]).level, .ok)
        let both = check([.lowPower, .hot(critical: false)])
        XCTAssertTrue(both.canLaunch)
        XCTAssertEqual(both.warnings.map(\.id), ["power"])
        XCTAssertTrue(both.warnings[0].detail.hasPrefix("Low Power Mode is on"))
        XCTAssertTrue(both.warnings[0].detail.contains("throttling the CPU and GPU"))
        XCTAssertTrue(check([.hot(critical: true)]).warnings[0].detail.contains("critically hot"))
    }

    func testPowerSummary() {
        XCTAssertEqual(PowerState.summary([]), PowerState.fullPerformance)
        XCTAssertEqual(PowerState.summary([.normal]), PowerState.fullPerformance)
        XCTAssertTrue(PowerState.summary([.lowPower]).hasPrefix("Low Power Mode is on"))
        XCTAssertTrue(PowerState.summary([.lowPower, .hot(critical: true)]).contains("critically hot"))
    }
}

final class NativeLaunchPreflightTests: XCTestCase {
    func testReadyWithMacLibraries() throws {
        let folder = try temporaryDirectory()
        let output = folder.appendingPathComponent("Game/Game")
        try write("\u{CF}\u{FA}\u{ED}\u{FE}", to: output)
        try write("lib", to: folder.appendingPathComponent("Game/libs/\(LaunchPreflight.nativeKernel)"))
        let check = LaunchPreflight(nativeOutput: output, libraries: folder.appendingPathComponent("Game/libs"),
                                    needsRosetta: false, freeBytes: 50 * 1024 * 1024 * 1024)
        XCTAssertEqual(check.checks.map(\.id), ["executable", "libraries", "folder", "disk"])
        XCTAssertEqual(check.level, .ok)
        XCTAssertEqual(check.checks[1].detail, "libkernel.prx in libs/")
    }

    func testMissingLibrariesAndRosettaBlockLaunch() throws {
        let folder = try temporaryDirectory()
        let output = folder.appendingPathComponent("Game/Game")
        try write("\u{CF}\u{FA}\u{ED}\u{FE}", to: output)
        let check = LaunchPreflight(nativeOutput: output, libraries: folder.appendingPathComponent("Game/libs"),
                                    needsRosetta: true, freeBytes: nil)
        XCTAssertFalse(check.canLaunch)
        XCTAssertEqual(check.failures.map(\.id), ["libraries", "rosetta"])
        XCTAssertTrue(check.failures[0].detail.contains("does not release them"))
        XCTAssertFalse(check.checks.contains { $0.title == "Wine runtime" })
    }

    func testCustomSearchPathIsOnlyWarned() throws {
        let folder = try temporaryDirectory()
        let output = folder.appendingPathComponent("Game/Game")
        try write("\u{CF}\u{FA}\u{ED}\u{FE}", to: output)
        let check = LaunchPreflight(nativeOutput: output, libraries: nil, needsRosetta: false, freeBytes: nil)
        XCTAssertTrue(check.canLaunch)
        XCTAssertEqual(check.warnings.map(\.id), ["libraries"])
    }

    func testMarkExecutableAddsExecuteBits() throws {
        let folder = try temporaryDirectory()
        let output = folder.appendingPathComponent("Game/Game")
        try write("\u{CF}\u{FA}\u{ED}\u{FE}", to: output)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: output.path)
        try LaunchPreflight.markExecutable(output)
        let mode = try FileManager.default.attributesOfItem(atPath: output.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o751)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: output.path))
    }
}
