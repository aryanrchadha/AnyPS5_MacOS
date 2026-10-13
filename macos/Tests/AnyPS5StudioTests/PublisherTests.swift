import Foundation
import XCTest
@testable import AnyPS5Studio

final class PublisherTests: XCTestCase {
    func testContentID() {
        let id = ContentID("up0006-PPSA01234_00-SAMPLEGAME000000")
        XCTAssertEqual(id?.raw, "UP0006-PPSA01234_00-SAMPLEGAME000000")
        XCTAssertEqual(id?.serviceId, "UP0006")
        XCTAssertEqual(id?.titleId, "PPSA01234")
        XCTAssertEqual(id?.publisher, .electronicArts)
        XCTAssertEqual(ContentID("EP0006-PPSA01234_00-SAMPLE")?.publisher, .electronicArts)
        XCTAssertNil(ContentID("UP9000-PPSA01234_00-SAMPLE")?.publisher)
        XCTAssertNotNil(ContentID("UP9000-PPSA01234_00-SAMPLE"))
        XCTAssertNil(ContentID("PPSA01234"))
        XCTAssertNil(ContentID("UP0006-PPSA01234-SAMPLE"))
        XCTAssertNil(ContentID("UP0006-PPSA01234_00-WAYTOOLONGLABEL00000"))
    }

    func testParamJson() throws {
        let json = """
        {"contentId": "EP0006-PPSA01234_00-SAMPLEGAME000000", "titleId": "PPSA01234",
         "localizedParameters": {"defaultLanguage": "en-US", "en-US": {"titleName": "Sample"}}}
        """
        let param = ParamJson(data: Data(json.utf8))
        XCTAssertEqual(param, ParamJson(title: "Sample", titleId: "PPSA01234", contentId: "EP0006-PPSA01234_00-SAMPLEGAME000000"))
        XCTAssertEqual(ParamJson(data: Data("[]".utf8)), ParamJson())

        let directory = try temporaryDirectory()
        try write(json, to: directory.appendingPathComponent("sce_sys/param.json"))
        XCTAssertEqual(ParamJson.read(besides: directory.appendingPathComponent("eboot.bin")).contentId,
                       "EP0006-PPSA01234_00-SAMPLEGAME000000")
        XCTAssertNil(ParamJson.read(besides: directory.appendingPathComponent("missing/eboot.bin")).contentId)
    }

    func testLibraryFilterSearchAndDiagnostics() {
        var ea = makeEntry("Football")
        ea.contentId = "UP0006-PPSA01234_00-SAMPLEGAME000000"
        var other = makeEntry("Platformer")
        other.contentId = "UP9000-PPSA05678_00-SAMPLEGAME000000"
        let entries = [ea, other, makeEntry("Unknown")]
        XCTAssertEqual(LibraryOrganizer.arrange(entries, query: "", sort: .title, favorites: [],
                                                status: .publisher(.electronicArts)).map(\.title), ["Football"])
        XCTAssertEqual(LibraryOrganizer.arrange(entries, query: "electronic arts", sort: .title, favorites: []).map(\.title), ["Football"])
        XCTAssertTrue(LibraryStatusFilter.allCases.contains(.publisher(.electronicArts)))
        XCTAssertEqual(LibraryStatusFilter.publisher(.electronicArts).title, "EA titles")
        let text = DiagnosticsReport(appVersion: "1.0", system: [], entry: ea, log: []).text
        XCTAssertTrue(text.contains("Content ID: UP0006-PPSA01234_00-SAMPLEGAME000000\nPublisher: Electronic Arts\n"))
        XCTAssertTrue(DiagnosticsReport(appVersion: "1.0", system: [], entry: other, log: []).text.contains("Publisher: unknown\n"))
    }

    func testFillContentIds() throws {
        let store = LibraryStore(directory: try temporaryDirectory())
        var known = makeEntry("Known", output: "/output/known.exe")
        known.contentId = "UP9000-PPSA05678_00-SAMPLEGAME000000"
        store.record(known)
        store.record(makeEntry("Old", output: "/output/old.exe"))
        store.record(makeEntry("Missing", output: "/output/missing.exe"))
        var reads: [String] = []
        store.fillContentIds { source in
            reads.append(source.path)
            return reads.count == 1 ? "UP0006-PPSA01234_00-SAMPLEGAME000000" : nil
        }
        XCTAssertEqual(reads.count, 2)
        XCTAssertEqual(store.entries.compactMap(\.publisher), [.electronicArts])
        XCTAssertEqual(store.entry(for: URL(fileURLWithPath: "/output/known.exe"))?.contentId, "UP9000-PPSA05678_00-SAMPLEGAME000000")
    }

    func testNotes() {
        XCTAssertEqual(Publisher.electronicArts.notes.map(\.title), ["Online modes", "Rosters and live content", "Frame rate"])
        XCTAssertEqual(Publisher.electronicArts.shortName, "EA")
        XCTAssertTrue(Publisher.electronicArts.summary.hasPrefix("Electronic Arts title. Online modes"))
    }
}
