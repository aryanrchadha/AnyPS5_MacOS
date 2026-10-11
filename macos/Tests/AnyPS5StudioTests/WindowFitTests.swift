import Foundation
import XCTest
@testable import AnyPS5Studio

final class WindowFitTests: XCTestCase {
    func testWindowThatFitsIsLeftAlone() {
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)
        XCTAssertNil(WindowFit.frame(CGRect(x: 80, y: 100, width: 1280, height: 760), in: visible))
    }

    func testOversizedWindowShrinksToTheVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1024, height: 743)
        let fitted = WindowFit.frame(CGRect(x: 0, y: 25, width: 1280, height: 840), in: visible)
        XCTAssertEqual(fitted, CGRect(x: 0, y: 0, width: 1024, height: 743))
    }

    func testWindowOffTheEdgeMovesBackInside() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(WindowFit.frame(CGRect(x: 600, y: 200, width: 1000, height: 700), in: visible),
                       CGRect(x: 440, y: 175, width: 1000, height: 700))
        XCTAssertEqual(WindowFit.frame(CGRect(x: -50, y: -20, width: 960, height: 600), in: visible),
                       CGRect(x: 0, y: 0, width: 960, height: 600))
    }

    func testSecondScreenOrigin() {
        let visible = CGRect(x: -1024, y: 0, width: 1024, height: 743)
        XCTAssertEqual(WindowFit.frame(CGRect(x: -1100, y: 0, width: 1280, height: 840), in: visible),
                       CGRect(x: -1024, y: 0, width: 1024, height: 743))
        XCTAssertNil(WindowFit.frame(CGRect(x: 0, y: 0, width: 100, height: 100), in: .zero))
    }
}
