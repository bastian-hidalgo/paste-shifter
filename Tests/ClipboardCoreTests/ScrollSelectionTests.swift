import XCTest
@testable import ClipboardCore

final class ScrollSelectionTests: XCTestCase {
    func testPreciseScrollAccumulatesSmallDeltas() {
        var scroll = ScrollSelection()
        XCTAssertNil(scroll.step(delta: -6, precise: true, momentum: false, time: 0))
        XCTAssertNil(scroll.step(delta: -6, precise: true, momentum: false, time: 0.02))
        XCTAssertEqual(scroll.step(delta: -6, precise: true, momentum: false, time: 0.04), 1)
    }
    func testMomentumAndRapidEventsDoNotSkipThroughHistory() {
        var scroll = ScrollSelection()
        XCTAssertEqual(scroll.step(delta: 20, precise: true, momentum: false, time: 0), -1)
        XCTAssertNil(scroll.step(delta: 100, precise: true, momentum: true, time: 0.15))
        XCTAssertNil(scroll.step(delta: 20, precise: true, momentum: false, time: 0.05))
        XCTAssertEqual(scroll.step(delta: 20, precise: true, momentum: false, time: 0.2), -1)
    }
    func testDirectionChangeAndNewGestureDiscardResidualMovement() {
        var scroll = ScrollSelection()
        XCTAssertNil(scroll.step(delta: 10, precise: true, momentum: false, time: 0))
        XCTAssertNil(scroll.step(delta: -10, precise: true, momentum: false, time: 0.05))
        XCTAssertNil(scroll.step(delta: -10, precise: true, momentum: false, time: 0.5))
        XCTAssertEqual(scroll.step(delta: -6, precise: true, momentum: false, time: 0.55), 1)
        scroll.reset()
        XCTAssertEqual(scroll.step(delta: 1, precise: false, momentum: false, time: 1), -1)
    }
}
