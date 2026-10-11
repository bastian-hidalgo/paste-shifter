import XCTest
@testable import ClipboardCore

final class ScrollCaptureTests: XCTestCase {
    func testScrollPassesThroughWhenPickerIsClosed() {
        var capture = ScrollCapture()
        XCTAssertEqual(capture.handle(delta: -20, precise: true, momentum: false, time: 0), .passThrough)
        capture.begin()
        XCTAssertEqual(capture.handle(delta: -20, precise: true, momentum: false, time: 1), .consumed(step: 1))
        capture.end()
        XCTAssertEqual(capture.handle(delta: -20, precise: true, momentum: false, time: 2), .passThrough)
    }
    func testMomentumIsSwallowedWithoutAdvancingSelectionAndReopeningResets() {
        var capture = ScrollCapture()
        capture.begin()
        XCTAssertEqual(capture.handle(delta: -100, precise: true, momentum: true, time: 0), .consumed(step: nil))
        XCTAssertEqual(capture.handle(delta: -8, precise: true, momentum: false, time: 1), .consumed(step: nil))
        capture.end(); capture.begin()
        XCTAssertEqual(capture.handle(delta: -8, precise: true, momentum: false, time: 1.01), .consumed(step: nil))
    }
}
