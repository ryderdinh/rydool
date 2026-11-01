import AppKit
import XCTest
@testable import Rydool

final class SelectionBehaviorTests: XCTestCase {
    func testPointerGesturesConvertToClampedSelectionGeometry() {
        let manager = SelectionManager(bounds: CGRect(x: 0, y: 0, width: 200, height: 100))
        let select = CaptureGesture.selection(anchor: CGPoint(x: 20, y: 20))
        XCTAssertTrue(select.isSelecting)
        XCTAssertEqual(select.selection(at: CGPoint(x: 300, y: 50), in: manager),
                       CGRect(x: 20, y: 20, width: 180, height: 30))
        let area = CGRect(x: 20, y: 10, width: 80, height: 50)
        let move = CaptureGesture.move(origin: area, pointer: CGPoint(x: 30, y: 20))
        XCTAssertEqual(move.selection(at: CGPoint(x: 50, y: 30), in: manager),
                       CGRect(x: 40, y: 20, width: 80, height: 50))
        XCTAssertNil(CaptureGesture.annotation.selection(at: .zero, in: manager))
    }

    func testDraggingResizesAcrossOppositeEdge() {
        let manager = SelectionManager(bounds: CGRect(x: 0, y: 0, width: 200, height: 100))
        let start = CGRect(x: 30, y: 20, width: 60, height: 40)
        XCTAssertEqual(manager.resized(start, handle: .left, by: CGSize(width: 80, height: 0)),
                       CGRect(x: 90, y: 20, width: 20, height: 40))
        XCTAssertEqual(manager.resized(start, handle: .bottomRight, by: CGSize(width: 200, height: 100)),
                       CGRect(x: 30, y: 20, width: 170, height: 80))
    }

    func testMoveClampsAndCornersTakePrecedence() {
        var manager = SelectionManager(bounds: CGRect(x: 0, y: 0, width: 200, height: 100))
        let selected = CGRect(x: 20, y: 10, width: 80, height: 50)
        manager.set(selected)
        XCTAssertEqual(manager.handle(at: CGPoint(x: 20, y: 10)), .topLeft)
        XCTAssertEqual(manager.handle(at: CGPoint(x: 20, y: 35)), .left)
        XCTAssertNil(manager.handle(at: CGPoint(x: 60, y: 35)))
        XCTAssertEqual(manager.moved(selected, by: CGSize(width: 500, height: -500)),
                       CGRect(x: 120, y: 0, width: 80, height: 50))
    }
}
