import Foundation
import XCTest
@testable import AnyPS5Studio

final class FlowLinesTests: XCTestCase {
    func testBreaksBeforeTheItemThatDoesNotFit() {
        XCTAssertEqual(FlowLines.lines(widths: [80, 90, 70, 100], available: 260, spacing: 6), [[0, 1, 2], [3]])
        XCTAssertEqual(FlowLines.lines(widths: [80, 90, 70, 100], available: 180, spacing: 6), [[0, 1], [2, 3]])
        XCTAssertEqual(FlowLines.lines(widths: [80, 90], available: 176, spacing: 6), [[0, 1]])
        XCTAssertEqual(FlowLines.lines(widths: [80, 90], available: 175, spacing: 6), [[0], [1]])
    }

    func testOversizedItemsGetTheirOwnLine() {
        XCTAssertEqual(FlowLines.lines(widths: [40, 500, 40], available: 200, spacing: 6), [[0], [1], [2]])
        XCTAssertEqual(FlowLines.lines(widths: [], available: 200, spacing: 6), [])
        XCTAssertEqual(FlowLines.lines(widths: [10, 10, 10], available: .infinity, spacing: 6), [[0, 1, 2]])
    }
}
