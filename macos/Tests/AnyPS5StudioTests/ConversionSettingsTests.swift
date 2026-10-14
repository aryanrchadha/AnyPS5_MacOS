import Foundation
import XCTest
@testable import AnyPS5Studio

final class ConversionSettingsTests: XCTestCase {
    private let input = URL(fileURLWithPath: "/games/PPSA01234/eboot.bin")

    func testWindowsArguments() {
        var settings = ConversionSettings()
        settings.windowsDiagnostics = true
        let output = URL(fileURLWithPath: "/out/Game/Game.exe")
        XCTAssertEqual(settings.arguments(input: input, output: output),
                       ["--windows", "--windows-gui", "--windows-diagnostics", "--to-intel", input.path, output.path])
    }

    func testMacArgumentsLowerForRosetta() {
        var settings = ConversionSettings()
        settings.target = .macos
        settings.windowsDiagnostics = true
        let output = URL(fileURLWithPath: "/out/Game/Game")
        XCTAssertEqual(settings.arguments(input: input, output: output),
                       ["--macos", "--to-rosetta", input.path, output.path])
        settings.toIntel = false
        XCTAssertEqual(settings.arguments(input: input, output: output), ["--macos", input.path, output.path])
    }

    func testLinuxArgumentsKeepIntelLowering() {
        var settings = ConversionSettings()
        settings.target = .linux
        settings.runPath = "/opt/anyps5/libs"
        let output = URL(fileURLWithPath: "/out/Game/Game.elf")
        XCTAssertEqual(settings.arguments(input: input, output: output),
                       ["--to-intel", "--rpath", "/opt/anyps5/libs", input.path, output.path])
    }

    func testExecutableNames() {
        let folder = URL(fileURLWithPath: "/out/Game", isDirectory: true)
        XCTAssertEqual(TargetPlatform.windows.executable(in: folder, name: "Game").path, "/out/Game/Game.exe")
        XCTAssertEqual(TargetPlatform.linux.executable(in: folder, name: "Game").path, "/out/Game/Game.elf")
        XCTAssertEqual(TargetPlatform.macos.executable(in: folder, name: "Game").path, "/out/Game/Game")
    }

    func testMacSearchPathValidation() {
        var settings = ConversionSettings()
        settings.target = .macos
        XCTAssertNil(settings.validationIssue)
        settings.runPath = "/Library/AnyPS5/libs"
        XCTAssertNil(settings.validationIssue)
        settings.runPath = "libs"
        XCTAssertEqual(settings.validationIssue, "macOS search paths must be absolute or start with $ORIGIN.")
        settings.target = .linux
        XCTAssertEqual(settings.validationIssue, "Linux search paths must be absolute or start with $ORIGIN.")
    }

    func testTargetsThatRunOnMac() {
        XCTAssertEqual(TargetPlatform.allCases.filter(\.runsOnMac), [.windows, .macos])
    }

    func testMacTargetRoundTrips() throws {
        let data = try JSONEncoder().encode(TargetPlatform.macos)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"macos\"")
        XCTAssertEqual(try JSONDecoder().decode(TargetPlatform.self, from: data), .macos)
    }
}
