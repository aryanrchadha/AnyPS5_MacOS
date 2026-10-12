import Foundation
import XCTest
@testable import AnyPS5Studio

final class WinePrefixTests: XCTestCase {
    private let executable = URL(fileURLWithPath: "/Games/Sample Game/eboot.exe")

    func testSeparatePrefixSitsBesideTheExecutable() {
        XCTAssertEqual(WinePrefix.folder(besides: executable).path, "/Games/Sample Game/wine-prefix")
        let global = ["WINEPREFIX": "/Users/pat/.wine", "WINEDEBUG": "-all"]
        XCTAssertEqual(WinePrefix.apply(to: global, separate: false, executable: executable), global)
        XCTAssertEqual(WinePrefix.apply(to: global, separate: true, executable: executable),
                       ["WINEPREFIX": "/Games/Sample Game/wine-prefix", "WINEDEBUG": "-all"])
    }

    func testTitleEnvironmentStillWins() {
        let profile = LaunchProfile(extraEnvironment: "WINEPREFIX=/Volumes/Fast/prefix", separatePrefix: true)
        let environment = profile.merged(over: WinePrefix.apply(to: [:], separate: profile.separatePrefix, executable: executable))
        XCTAssertEqual(environment["WINEPREFIX"], "/Volumes/Fast/prefix")
    }

    func testWinetricksCommand() {
        XCTAssertEqual(WinePrefix.winetricksCommand(verb: "vcrun2022", environment: [:], wine: nil), "winetricks vcrun2022")
        XCTAssertEqual(WinePrefix.winetricksCommand(verb: "vcrun2022",
                                                    environment: ["WINEPREFIX": "/Games/Pat's Game/wine-prefix"],
                                                    wine: URL(fileURLWithPath: "/opt/homebrew/bin/wine64")),
                       "WINEPREFIX='/Games/Pat'\\''s Game/wine-prefix' WINE='/opt/homebrew/bin/wine64' winetricks vcrun2022")
    }

    func testProfileDecodesWithoutTheFlag() throws {
        let old = try JSONDecoder().decode(LaunchProfile.self, from: Data(#"{"metalHUD":true}"#.utf8))
        XCTAssertFalse(old.separatePrefix)
        let round = try JSONDecoder().decode(LaunchProfile.self, from: JSONEncoder().encode(LaunchProfile(separatePrefix: true)))
        XCTAssertTrue(round.separatePrefix)
    }

    func testWinetricksVerbs() {
        func verb(_ dll: String) -> String? {
            CrashFinding(kind: .missingLibrary, headline: "Missing library: \(dll)", detail: nil, subject: dll).winetricksVerb
        }
        XCTAssertEqual(verb("MSVCP140.dll"), "vcrun2022")
        XCTAssertEqual(verb("VCRUNTIME140_1.dll"), "vcrun2022")
        XCTAssertEqual(verb("D3DCOMPILER_43.dll"), "d3dcompiler_47")
        XCTAssertNil(verb("steam_api64.dll"))
        XCTAssertNil(CrashFinding(kind: .exception, headline: "Uncaught X", detail: nil, subject: "X").winetricksVerb)
    }
}
