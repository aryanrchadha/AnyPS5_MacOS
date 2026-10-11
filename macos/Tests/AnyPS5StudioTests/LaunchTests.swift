import Foundation
import XCTest
@testable import AnyPS5Studio

final class LaunchProfileTests: XCTestCase {
    func testOlderProfilesDecode() throws {
        let profile = try JSONDecoder().decode(LaunchProfile.self, from: Data(#"{"metalHUD":true,"extraEnvironment":"A=1"}"#.utf8))
        XCTAssertTrue(profile.metalHUD)
        XCTAssertFalse(profile.backupSavesOnLaunch)
        XCTAssertFalse(profile.quietWine)
        XCTAssertNil(profile.wineRuntimePath)
        XCTAssertEqual(try JSONDecoder().decode(LaunchProfile.self, from: Data("{}".utf8)), LaunchProfile())
    }

    func testRoundTrip() throws {
        let profile = LaunchProfile(metalHUD: true, extraEnvironment: "X=1", backupSavesOnLaunch: true, quietWine: true, wineRuntimePath: "/w")
        XCTAssertEqual(try JSONDecoder().decode(LaunchProfile.self, from: JSONEncoder().encode(profile)), profile)
    }

    func testEnvironmentPrecedence() {
        var profile = LaunchProfile(quietWine: true)
        XCTAssertEqual(profile.environment, ["WINEDEBUG": "-all"])
        XCTAssertEqual(profile.merged(over: ["WINEDEBUG": "warn+all"])["WINEDEBUG"], "-all")
        profile.extraEnvironment = "WINEDEBUG=+seh\n# comment\nbad key=x\nFOO=1"
        profile.metalHUD = true
        XCTAssertEqual(profile.environment, ["WINEDEBUG": "+seh", "FOO": "1", "MTL_HUD_ENABLED": "1"])
    }
}

final class SessionLogTests: XCTestCase {
    func testRetentionKeepsNewestByName() throws {
        let folder = try temporaryDirectory()
        for day in 10...22 { try write("x", to: folder.appendingPathComponent("Session 2026-10-\(day) 10.00.00.log")) }
        try write("keep", to: folder.appendingPathComponent("notes.txt"))
        let logs = SessionLog.logs(in: folder)
        XCTAssertEqual(logs.count, 13)
        XCTAssertEqual(logs.first?.lastPathComponent, "Session 2026-10-22 10.00.00.log")
        XCTAssertEqual(SessionLog.expired(logs).map(\.lastPathComponent),
                       ["Session 2026-10-12 10.00.00.log", "Session 2026-10-11 10.00.00.log", "Session 2026-10-10 10.00.00.log"])
        XCTAssertEqual(SessionLog.expired(logs, keeping: -1).count, 13)
    }

    func testText() {
        let lines = [LogLine(id: 1, text: "$ wine game.exe", source: .system),
                     LogLine(id: 2, text: "hello", source: .stdout),
                     LogLine(id: 3, text: "err:module", source: .stderr)]
        let text = SessionLog.text(lines, title: "Game", started: Date(timeIntervalSince1970: 0), duration: 61.7, exitCode: 3)
        XCTAssertTrue(text.contains("# Duration: 61s"))
        XCTAssertTrue(text.contains("# Exit code: 3"))
        XCTAssertTrue(text.hasSuffix("# $ wine game.exe\nhello\n! err:module\n"))
    }
}

final class LauncherTests: XCTestCase {
    func testScriptLogsBacksUpAndPassesExitCode() throws {
        let root = try temporaryDirectory()
        let title = "Game O'Brien"
        let game = root.appendingPathComponent(title, isDirectory: true)
        try write("save", to: game.appendingPathComponent("_sd/user/slot1"))
        let wine = root.appendingPathComponent("bin/wine")
        try write("#!/bin/sh\necho \"out $3\"\necho err >&2\nexit 7\n", to: wine)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        let ditto = root.appendingPathComponent("bin/ditto")
        try write("#!/bin/sh\nfor last; do :; done\necho zip > \"$last\"\n", to: ditto)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ditto.path)
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        for day in 1...12 { try write("x", to: logs.appendingPathComponent("Session 2026-01-\(String(format: "%02d", day)) 10.00.00.log")) }
        for day in 1...6 { try write("x", to: backups.appendingPathComponent("Auto 2026-01-0\(day) 10.00.00.zip")) }
        try write("x", to: backups.appendingPathComponent("Saves manual.zip"))

        let script = LauncherBuilder.script(executable: game.appendingPathComponent("\(title).exe"), wine: wine,
                                            environment: ["WINEDEBUG": "-all"], title: title,
                                            logFolder: logs, backupFolder: backups)
            .replacingOccurrences(of: LauncherBuilder.ditto, with: ditto.path)
        let launcher = root.appendingPathComponent("launch")
        try write(script, to: launcher)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [launcher.path, "first", "two words"]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 7)
        let sessionLogs = SessionLog.logs(in: logs)
        XCTAssertEqual(sessionLogs.count, SessionLog.retention)
        let newest = try String(contentsOf: sessionLogs[0], encoding: .utf8)
        XCTAssertTrue(newest.hasPrefix("# Game O'Brien\n"))
        XCTAssertTrue(newest.contains("out two words\n"))
        XCTAssertTrue(newest.contains("err\n"))
        XCTAssertTrue(newest.hasSuffix("# Exit code: 7\n"))
        let archives = SaveData.backups(in: backups)
        XCTAssertEqual(archives.filter(SaveData.isAutomatic).count, SaveData.automaticRetention)
        XCTAssertTrue(archives.contains { $0.url.lastPathComponent == "Saves manual.zip" })
    }

    func testPlainScriptExecsWine() {
        let script = LauncherBuilder.script(executable: URL(fileURLWithPath: "/g/G.exe"), wine: URL(fileURLWithPath: "/w"), environment: ["bad key": "x"])
        XCTAssertEqual(script, "#!/bin/sh\ncd '/g' || exit 1\nexec '/w' '/g/G.exe' \"$@\"\n")
    }
}
