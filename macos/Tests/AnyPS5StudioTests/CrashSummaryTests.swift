import Foundation
import XCTest
@testable import AnyPS5Studio

final class CrashSummaryTests: XCTestCase {
    func testMissingFunctionFromCoredumpAndTerminate() {
        let summary = CrashSummary(lines: [
            "# Launch via Wine",
            "! [coredump] uncaught C++ exception 0x7ff1 of type std::runtime_error, what(): 5nc2gdLNsok not implemented",
            "! terminate called after throwing an instance of 'std::runtime_error'",
            "!   what():  sceFontFtSupportOtf not implemented",
            "! [coredump] uncaught C++ exception 0x7ff2 of type std::runtime_error, what(): 5nc2gdLNsok not implemented",
        ])
        XCTAssertEqual(summary.findings.map(\.headline),
                       ["Missing function: 5nc2gdLNsok", "Missing function: sceFontFtSupportOtf"])
        XCTAssertEqual(summary.findings.map(\.kind), [.missingFunction, .missingFunction])
        XCTAssertEqual(summary.headline, "Missing function: 5nc2gdLNsok")
    }

    func testExceptions() {
        let summary = CrashSummary(text: """
        terminate called after throwing an instance of 'std::out_of_range'
          what():  vector::_M_range_check
        [coredump] uncaught C++ exception 0x1 of type GuestError
        [libc] unhandled exception 'std::bad_alloc' thrown from 0x7ff6
        libSceFont: ANYPS5_SYSTEM_FONTS is not a directory: /x
        """)
        XCTAssertEqual(summary.findings.map(\.headline), [
            "Uncaught std::out_of_range: vector::_M_range_check",
            "Uncaught GuestError",
            "Uncaught std::bad_alloc",
        ])
    }

    func testFaultsLibrariesAndGPU() {
        let summary = CrashSummary(lines: [
            "! ",
            "! FATAL: unhandled exception 0xc000001d on thread 4242 'GameMain'",
            "!   rip eboot.exe+0x1a2b3c",
            "! FATAL: unhandled exception 0x12345678 on thread 7 ''",
            "! err:module:import_dll Library VCRUNTIME140_1.dll (which is needed by L\"Z:\\\\Game\\\\eboot.exe\") not found",
            "! wine: Unhandled page fault on read access to 0000000000000000 at address 0000000140001000",
            "! Vulkan: no usable device whose name contains ANYPS5_GPU=\"Radeon\"; devices: Apple M3 Max",
        ])
        XCTAssertEqual(summary.findings.count, CrashSummary.limit)
        XCTAssertEqual(summary.findings[0].headline, "Fault 0xC000001D (illegal instruction) on thread 4242 \u{2018}GameMain\u{2019}")
        XCTAssertEqual(summary.findings[0].detail, "at eboot.exe+0x1a2b3c")
        XCTAssertEqual(summary.findings[1].headline, "Fault 0x12345678 on thread 7")
        XCTAssertNil(summary.findings[1].detail)
        XCTAssertEqual(summary.findings[2].headline, "Missing library: VCRUNTIME140_1.dll")
        XCTAssertEqual(summary.findings[3].headline, "Wine: unhandled page fault on read access to 0000000000000000 at address 0000000140001000")
        XCTAssertEqual(summary.findings[4].kind, .gpu)
    }

    func testCleanLogHasNoFindings() {
        let summary = CrashSummary(text: "# Started\nPhysical device candidate: Apple M3 Max\nwhat a day\n# Exit code: 0\n")
        XCTAssertTrue(summary.findings.isEmpty)
        XCTAssertNil(summary.headline)
    }

    func testReadsTheTailOfALog() throws {
        let folder = try temporaryDirectory()
        let log = folder.appendingPathComponent("Session.log")
        let padding = String(repeating: "x", count: 1023) + "\n"
        let early = "! [coredump] uncaught C++ exception 0x1 of type std::runtime_error, what(): early not implemented\n"
        let late = "! [coredump] uncaught C++ exception 0x1 of type std::runtime_error, what(): late not implemented\n"
        try write(early + String(repeating: padding, count: 600) + late, to: log)
        XCTAssertEqual(CrashSummary.read(log: log)?.headline, "Missing function: late")
        XCTAssertNil(CrashSummary.read(log: folder.appendingPathComponent("missing.log")))
    }

    func testCompatibilityReportListsRedactedCause() {
        let entry = makeEntry("Game", titleId: "PPSA00001",
                              sessions: [PlaySession(start: Date(timeIntervalSince1970: 0), duration: 60, exitCode: 3)])
        let crash = CrashSummary(lines: [
            "terminate called after throwing an instance of 'std::filesystem::filesystem_error'",
            "  what():  cannot open: Z:\\Users\\pat\\Games\\a.bin and /Users/pat/Games/b.bin",
            "[coredump] uncaught C++ exception 0x1 of type std::runtime_error, what(): sceX not implemented",
        ])
        let report = CompatibilityReport(entry: entry, mac: "Apple M2", macOS: "macOS 15", runtime: nil, appVersion: "1",
                                         crash: crash, home: "/Users/pat").markdown
        XCTAssertTrue(report.contains("| Likely cause | Uncaught std::filesystem::filesystem_error: cannot open: ~\\Games\\a.bin and ~/Games/b.bin; Missing function: sceX |"), report)
        XCTAssertFalse(report.contains("pat"))

        let clean = CompatibilityReport(entry: makeEntry("Game", sessions: [PlaySession(start: Date(), duration: 1, exitCode: 0)]),
                                        mac: "M", macOS: "m", runtime: nil, appVersion: "1", crash: crash, home: "/Users/pat").markdown
        XCTAssertFalse(clean.contains("Likely cause"))
    }
}
