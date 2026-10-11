import XCTest
@testable import ClipboardCore

final class ReleaseSelectionTests: XCTestCase {
    func testWaitsForBothModifiersAndCommitsOnlyOnce() {
        var selection = ReleaseSelection()
        selection.arm()
        XCTAssertFalse(selection.commit(optionHeld: true, shiftHeld: true))
        XCTAssertFalse(selection.commit(optionHeld: true, shiftHeld: false))
        XCTAssertTrue(selection.commit(optionHeld: false, shiftHeld: false))
        XCTAssertFalse(selection.commit(optionHeld: false, shiftHeld: false))
    }
    func testMenuOpenAndCancelledPickerNeverCommitOnRelease() {
        var selection = ReleaseSelection()
        XCTAssertFalse(selection.commit(optionHeld: false, shiftHeld: false))
        selection.arm()
        selection.cancel()
        XCTAssertFalse(selection.commit(optionHeld: false, shiftHeld: false))
        selection.arm()
        XCTAssertFalse(selection.commit(optionHeld: false, shiftHeld: true))
        XCTAssertTrue(selection.commit(optionHeld: false, shiftHeld: false))
    }
}
