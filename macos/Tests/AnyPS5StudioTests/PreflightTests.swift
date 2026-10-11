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
}
