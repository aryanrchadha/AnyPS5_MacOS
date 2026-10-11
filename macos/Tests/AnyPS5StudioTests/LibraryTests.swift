import Foundation
import XCTest
@testable import AnyPS5Studio

final class LibraryStoreTests: XCTestCase {
    func testMergeAddsAndFillsWithoutRemoving() throws {
        let store = LibraryStore(directory: try temporaryDirectory())
        let first = PlaySession(start: Date(timeIntervalSince1970: 100), duration: 10, exitCode: 0)
        let second = PlaySession(start: Date(timeIntervalSince1970: 200), duration: 20, exitCode: 0)
        store.record(makeEntry("A", sessions: [first]))
        var incoming = makeEntry("A", output: "/output/A/../A/A.exe", sessions: [first, second], status: .playable)
        incoming.notes = "imported"
        let result = store.merge([incoming, makeEntry("B")])
        XCTAssertEqual(result, LibraryMergeResult(added: 1, updated: 1, unchanged: 0))
        let merged = try XCTUnwrap(store.entry(for: URL(fileURLWithPath: "/output/A/A.exe")))
        XCTAssertEqual(merged.sessions?.count, 2)
        XCTAssertEqual(merged.status, .playable)
        XCTAssertEqual(merged.notes, "imported")
        XCTAssertEqual(store.merge([incoming]), LibraryMergeResult(added: 0, updated: 0, unchanged: 1))
    }

    func testUnreadableLibraryIsSetAside() throws {
        let directory = try temporaryDirectory()
        try write("{ not json", to: directory.appendingPathComponent("library.json"))
        let store = LibraryStore(directory: directory)
        XCTAssertTrue(store.entries.isEmpty)
        let aside = try XCTUnwrap(store.setAside)
        XCTAssertEqual(try String(contentsOf: aside, encoding: .utf8), "{ not json")
        store.record(makeEntry("New"))
        XCTAssertEqual(LibraryStore(directory: directory).entries.count, 1)
    }

    func testStatusSurvivesReconversion() throws {
        let directory = try temporaryDirectory()
        let store = LibraryStore(directory: directory)
        let output = URL(fileURLWithPath: "/output/A/A.exe")
        store.record(makeEntry("A"))
        store.setStatus(.inGame, notes: "  crackle \n", for: output)
        store.record(makeEntry("A v2", output: "/output/A/A.exe"))
        let entry = try XCTUnwrap(LibraryStore(directory: directory).entry(for: output))
        XCTAssertEqual(entry.title, "A v2")
        XCTAssertEqual(entry.status, .inGame)
        XCTAssertEqual(entry.notes, "crackle")
    }

    func testArchiveRejectsNewerFormat() throws {
        var archive = LibraryArchive(exportedAt: Date(timeIntervalSince1970: 0), entries: [makeEntry("A")], favorites: ["/a"])
        XCTAssertEqual(try LibraryArchive.read(LibraryArchive.encoder.encode(archive)), archive)
        archive.version = LibraryArchive.currentVersion + 1
        XCTAssertThrowsError(try LibraryArchive.read(LibraryArchive.encoder.encode(archive)))
    }
}

final class LibraryOrganizerTests: XCTestCase {
    func testStatusFilterAndSearch() {
        var noted = makeEntry("D", status: .playable)
        noted.notes = "audio crackle"
        let entries = [makeEntry("A", status: .playable), makeEntry("B"), makeEntry("C", status: .menus), noted]
        func titles(_ filter: LibraryStatusFilter, _ query: String = "") -> [String] {
            LibraryOrganizer.arrange(entries, query: query, sort: .title, favorites: [], status: filter).map(\.title)
        }
        XCTAssertEqual(titles(.all), ["A", "B", "C", "D"])
        XCTAssertEqual(titles(.notSet), ["B"])
        XCTAssertEqual(titles(.status(.playable)), ["A", "D"])
        XCTAssertEqual(titles(.all, "CRACKLE"), ["D"])
        XCTAssertEqual(titles(.all, "menus"), ["C"])
    }

    func testPlayActivityBuckets() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = 1_791_590_400.0
        let day = 86_400.0
        let entry = makeEntry("X", sessions: [PlaySession(start: Date(timeIntervalSince1970: today + 3600), duration: 1800, exitCode: 0),
                                              PlaySession(start: Date(timeIntervalSince1970: today - 2 * day), duration: 3600, exitCode: 1),
                                              PlaySession(start: Date(timeIntervalSince1970: today - 7 * day), duration: 9999, exitCode: 0)])
        let activity = PlayActivity(entries: [entry], now: Date(timeIntervalSince1970: today + 15 * 3600), calendar: calendar)
        XCTAssertEqual(activity.days.count, 7)
        XCTAssertEqual(activity.days.last?.duration, 1800)
        XCTAssertEqual(activity.total, 5400)
        XCTAssertEqual(activity.sessions, 2)
        XCTAssertEqual(PlayActivity.format(3 * 3600 + 12 * 60), "3h 12m")
    }

    func testCompatibilityReport() {
        var entry = makeEntry("Game | Two", titleId: "PPSA02929", status: .inGame)
        entry.notes = "line one\n\nline two"
        let report = CompatibilityReport(entry: entry, mac: "Apple M2", macOS: "macOS 15", runtime: "CrossOver", appVersion: "1").markdown
        XCTAssertTrue(report.hasPrefix("### Game \\| Two (PPSA02929)\n"))
        XCTAssertTrue(report.contains("| Status | In game |"))
        XCTAssertTrue(report.hasSuffix("> line one\n>\n> line two\n"))
        XCTAssertFalse(report.contains("/output"))
    }
}

final class StudioLinkTests: XCTestCase {
    func testParsing() {
        func link(_ text: String) -> StudioLink? { URL(string: text).flatMap(StudioLink.init(url:)) }
        XCTAssertEqual(link("anyps5://launch/PPSA02929"), .launch("PPSA02929"))
        XCTAssertEqual(link("ANYPS5://Launch?Title=Dreaming%20Sarah"), .launch("Dreaming Sarah"))
        XCTAssertEqual(link("anyps5://library"), .library)
        XCTAssertNil(link("anyps5://launch?title=%20"))
        XCTAssertNil(link("anyps5://delete/x"))
        XCTAssertNil(link("https://launch/x"))
    }

    func testRoundTripAndMatch() throws {
        let special = makeEntry("A & B=C+D é")
        let url = try XCTUnwrap(StudioLink.launchURL(for: special))
        XCTAssertEqual(url.absoluteString, "anyps5://launch?title=A%20%26%20B%3DC%2BD%20%C3%A9")
        XCTAssertEqual(StudioLink(url: url), .launch("A & B=C+D é"))
        let older = makeEntry("Sarah", titleId: "PPSA02929", output: "/o/1.exe", convertedAt: 100)
        let newer = makeEntry("Sarah", titleId: "PPSA02929", output: "/o/2.exe", convertedAt: 300)
        XCTAssertEqual(StudioLink.match("ppsa02929", in: [older, newer])?.output, newer.output)
        XCTAssertNil(StudioLink.match("nope", in: [older]))
    }
}

final class PadSnapshotTests: XCTestCase {
    func testRestNote() {
        XCTAssertEqual(Set(PadButton.groups.flatMap { $0 }), Set(PadButton.allCases))
        var snapshot = PadSnapshot()
        snapshot.leftStick = .init(x: 0.06, y: 0.08)
        XCTAssertEqual(snapshot.restNote(for: snapshot.leftStick), "0.10 off centre at rest")
        snapshot.pressed = [.cross]
        XCTAssertNil(snapshot.restNote(for: snapshot.leftStick))
    }
}
