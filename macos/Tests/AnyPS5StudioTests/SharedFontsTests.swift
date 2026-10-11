import Foundation
import XCTest
@testable import AnyPS5Studio

final class SharedFontsTests: XCTestCase {
    private func fixture() throws -> (executable: URL, shared: URL) {
        let root = try temporaryDirectory()
        let executable = root.appendingPathComponent("Game/Game.exe")
        try write("MZ", to: executable)
        let shared = root.appendingPathComponent("Shared Fonts", isDirectory: true)
        try write("font", to: shared.appendingPathComponent("SST-Roman.otf"))
        try write("font", to: shared.appendingPathComponent("NotoSansCJK-Regular.TTC"))
        try write("text", to: shared.appendingPathComponent("README.txt"))
        return (executable, shared)
    }

    func testLinksTitleWithoutFonts() throws {
        let (executable, shared) = try fixture()
        XCTAssertEqual(SharedFonts.source(besides: executable), .none)
        XCTAssertTrue(try SharedFonts.link(besides: executable, shared: shared))
        let local = SharedFonts.localFolder(besides: executable)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: local.path), shared.path)
        XCTAssertEqual(SharedFonts.source(besides: executable), .linked(2))
        XCTAssertFalse(try SharedFonts.link(besides: executable, shared: shared))
    }

    func testKeepsOwnFontsAndOwnLinks() throws {
        let (executable, shared) = try fixture()
        let local = SharedFonts.localFolder(besides: executable)
        try write("font", to: local.appendingPathComponent("SST-Bold.otf"))
        XCTAssertFalse(try SharedFonts.link(besides: executable, shared: shared))
        XCTAssertEqual(SharedFonts.source(besides: executable), .own(1))

        let other = try fixture()
        let custom = other.shared.deletingLastPathComponent().appendingPathComponent("Custom", isDirectory: true)
        try write("font", to: custom.appendingPathComponent("SST-Light.otf"))
        let otherLocal = SharedFonts.localFolder(besides: other.executable)
        try FileManager.default.createSymbolicLink(atPath: otherLocal.path, withDestinationPath: custom.path)
        XCTAssertFalse(try SharedFonts.link(besides: other.executable, shared: other.shared))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: otherLocal.path), custom.path)
    }

    func testReplacesBrokenLinkAndSkipsEmptySharedFolder() throws {
        let (executable, shared) = try fixture()
        let local = SharedFonts.localFolder(besides: executable)
        try FileManager.default.createSymbolicLink(atPath: local.path, withDestinationPath: "/nonexistent/anyps5-fonts")
        XCTAssertTrue(try SharedFonts.link(besides: executable, shared: shared))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: local.path), shared.path)

        let empty = try fixture()
        let emptyShared = empty.shared.deletingLastPathComponent().appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyShared, withIntermediateDirectories: true)
        XCTAssertFalse(try SharedFonts.link(besides: empty.executable, shared: emptyShared))
        XCTAssertFalse(FileManager.default.fileExists(atPath: SharedFonts.localFolder(besides: empty.executable).path))
    }

    func testDetachOnlyRemovesSharedOrBrokenLinks() throws {
        let (executable, shared) = try fixture()
        let local = SharedFonts.localFolder(besides: executable)
        try SharedFonts.link(besides: executable, shared: shared)
        XCTAssertTrue(SharedFonts.isShared(besides: executable, shared: shared))
        try SharedFonts.detachShared(besides: executable, shared: shared)
        XCTAssertFalse(SharedFonts.isLink(local))
        XCTAssertEqual(SharedFonts.fonts(in: shared).count, 2)

        let custom = shared.deletingLastPathComponent().appendingPathComponent("Custom", isDirectory: true)
        try write("font", to: custom.appendingPathComponent("SST-Light.otf"))
        try FileManager.default.createSymbolicLink(atPath: local.path, withDestinationPath: custom.path)
        try SharedFonts.detachShared(besides: executable, shared: shared)
        XCTAssertTrue(SharedFonts.isLink(local))
        XCTAssertFalse(SharedFonts.isShared(besides: executable, shared: shared))

        try FileManager.default.removeItem(at: local)
        try FileManager.default.createSymbolicLink(atPath: local.path, withDestinationPath: "/nonexistent/anyps5-fonts")
        try SharedFonts.detachShared(besides: executable, shared: shared)
        XCTAssertFalse(SharedFonts.isLink(local))
        try SharedFonts.detachShared(besides: executable, shared: shared)
    }

    func testCollectAndCopy() throws {
        let (executable, shared) = try fixture()
        let single = shared.deletingLastPathComponent().appendingPathComponent("NotoSans-Bold.ttf")
        try write("font", to: single)
        let collected = SharedFonts.collect(from: [shared, single, shared.appendingPathComponent("README.txt")])
        XCTAssertEqual(collected.map(\.lastPathComponent), ["NotoSansCJK-Regular.TTC", "SST-Roman.otf", "NotoSans-Bold.ttf"])
        let destination = SharedFonts.localFolder(besides: executable)
        try SharedFonts.copy(collected, to: destination)
        try SharedFonts.copy(collected, to: destination)
        XCTAssertEqual(SharedFonts.fonts(in: destination).count, 3)
        XCTAssertEqual(SharedFonts.source(besides: executable), .own(3))
    }
}
