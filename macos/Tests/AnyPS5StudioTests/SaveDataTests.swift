import Foundation
import XCTest
@testable import AnyPS5Studio

final class SaveDataTests: XCTestCase {
    func testAutomaticBackupsExpireByName() throws {
        let folder = try temporaryDirectory()
        for day in 1...7 { try write("x", to: folder.appendingPathComponent("Auto 2026-10-0\(day) 10.00.00.zip")) }
        try write("y", to: folder.appendingPathComponent("Saves manual.zip"))
        let backups = SaveData.backups(in: folder)
        XCTAssertEqual(backups.count, 8)
        XCTAssertEqual(SaveData.expiredAutomaticBackups(in: backups).map(\.url.lastPathComponent).sorted(),
                       ["Auto 2026-10-01 10.00.00.zip", "Auto 2026-10-02 10.00.00.zip"])
        XCTAssertTrue(SaveData.expiredAutomaticBackups(in: backups, keeping: 10).isEmpty)
    }

    func testBackupNames() {
        let manual = SaveData.backupName(for: Date(timeIntervalSince1970: 0))
        let automatic = SaveData.backupName(for: Date(timeIntervalSince1970: 0), automatic: true)
        XCTAssertTrue(manual.hasPrefix("Saves ") && automatic.hasPrefix("Auto "))
        XCTAssertFalse(manual.contains(":") || manual.contains("/"))
        XCTAssertEqual(SaveData.backupFolder(title: "Game: Part/2", titleId: "PPSA1", root: URL(fileURLWithPath: "/r")).lastPathComponent,
                       "Game- Part-2 (PPSA1)")
    }

    func testConfiguredBackupRoot() {
        XCTAssertEqual(SaveData.backupRoot(configured: nil), SaveData.defaultBackupRoot)
        XCTAssertEqual(SaveData.backupRoot(configured: "relative"), SaveData.defaultBackupRoot)
        XCTAssertEqual(SaveData.backupRoot(configured: " /Volumes/Ext/Saves/ ").path, "/Volumes/Ext/Saves")
    }

    func testEntitlements() throws {
        let file = EntitlementsFile(contents: "# owned\nSEASONPASS01 ; trailing\nSEASONPASS01\nTHISLABELISWAYTOOLONG\n")
        XCTAssertEqual(file.labels, ["SEASONPASS01"])
        XCTAssertEqual(file.issues.count, 1)
        var copy = file
        XCTAssertThrowsError(try copy.add("ABCDEFGHIJKLMNOP"))
        XCTAssertNoThrow(try copy.add("ABCDEFGHIJKLMNO"))
    }
}

final class StorageTests: XCTestCase {
    func testMeasureSkipsSymlinkedGameFiles() throws {
        let root = try temporaryDirectory()
        try write("exe", to: root.appendingPathComponent("out/A/A.exe"))
        try write("cache", to: root.appendingPathComponent("out/A/shader_cache/s"))
        try write(String(repeating: "g", count: 200_000), to: root.appendingPathComponent("game/big"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("out/A/app0"),
                                                   withDestinationURL: root.appendingPathComponent("game"))
        let report = StorageReport.measure(outputs: [root.appendingPathComponent("out/A/A.exe"), root.appendingPathComponent("out/A/../A/A.exe"),
                                                     root.appendingPathComponent("out/Gone/G.exe")],
                                           backupRoot: root.appendingPathComponent("none"), logRoot: root.appendingPathComponent("none"))
        XCTAssertEqual(report.titleCount, 1)
        XCTAssertGreaterThan(report.shaderCaches, 0)
        XCTAssertLessThan(report.titles, 200_000)
    }

    func testCleanupOnlyRemovesCachesAndSessionLogs() throws {
        let root = try temporaryDirectory()
        try write("cache", to: root.appendingPathComponent("out/A/shader_cache/s"))
        try write("save", to: root.appendingPathComponent("out/A/_sd/save"))
        try write("log", to: root.appendingPathComponent("logs/A/Session 2026-01-01 10.00.00.log"))
        try write("log", to: root.appendingPathComponent("logs/Keep/Session 2026-01-01 10.00.00.log"))
        try write("mine", to: root.appendingPathComponent("logs/Keep/notes.txt"))
        let output = root.appendingPathComponent("out/A/A.exe")
        XCTAssertEqual(StorageCleanup.clearShaderCaches(outputs: [output, output]).cleared, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("out/A/_sd/save").path))
        XCTAssertEqual(StorageCleanup.deleteSessionLogs(root: root.appendingPathComponent("logs")), 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("logs/A").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("logs/Keep/notes.txt").path))
    }
}
