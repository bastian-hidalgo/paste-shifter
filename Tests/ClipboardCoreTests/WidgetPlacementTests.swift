import XCTest
import CoreGraphics
@testable import ClipboardCore

final class WidgetPlacementTests: XCTestCase {
    private let size = CGSize(width: 360, height: 44)
    func testAppearsNextToMouse() {
        let point = WidgetPlacement.nearMouse(CGPoint(x: 500, y: 500), size: size, in: CGRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(point, CGPoint(x: 514, y: 442))
    }
    func testFlipsAtEdgesOnScreenWithNegativeCoordinates() {
        let screen = CGRect(x: -1440, y: -100, width: 1440, height: 900)
        let mouse = CGPoint(x: -10, y: -95)
        let point = WidgetPlacement.nearMouse(mouse, size: size, in: screen)
        XCTAssertLessThan(point.x, mouse.x)
        XCTAssertGreaterThan(point.y, mouse.y)
        XCTAssertTrue(screen.contains(CGRect(origin: point, size: size)))
    }
}
