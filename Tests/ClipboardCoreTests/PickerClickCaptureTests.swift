import XCTest
@testable import ClipboardCore

final class PickerClickCaptureTests: XCTestCase {
    func testCompleteClickIsConsumedAndConfirmsOnlyOnRelease() {
        var click = PickerClickCapture()
        click.begin()
        XCTAssertEqual(click.handle(.down), .consumed(confirm: false))
        XCTAssertEqual(click.handle(.drag), .consumed(confirm: false))
        XCTAssertEqual(click.handle(.up), .consumed(confirm: true))
        XCTAssertEqual(click.handle(.up), .passThrough)
    }
    func testCancelDuringClickStillSwallowsReleaseWithoutPasting() {
        var click = PickerClickCapture()
        click.begin()
        XCTAssertEqual(click.handle(.down), .consumed(confirm: false))
        click.end()
        XCTAssertTrue(click.isTracking)
        XCTAssertEqual(click.handle(.drag), .consumed(confirm: false))
        XCTAssertEqual(click.handle(.up), .consumed(confirm: false))
        XCTAssertFalse(click.isTracking)
        XCTAssertEqual(click.handle(.down), .passThrough)
    }
    func testReleaseOfPreviousCancelledClickDoesNotConfirmReopenedPicker() {
        var click = PickerClickCapture()
        click.begin()
        _ = click.handle(.down)
        click.end(); click.begin()
        XCTAssertEqual(click.handle(.up), .consumed(confirm: false))
        XCTAssertEqual(click.handle(.down), .consumed(confirm: false))
        XCTAssertEqual(click.handle(.up), .consumed(confirm: true))
    }
    func testOpeningDuringAnExistingDragDoesNotHijackIt() {
        var click = PickerClickCapture()
        click.begin()
        XCTAssertEqual(click.handle(.drag), .passThrough)
        XCTAssertEqual(click.handle(.up), .passThrough)
    }
}
