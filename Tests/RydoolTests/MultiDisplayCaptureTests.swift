import AppKit
import XCTest
@testable import Rydool

final class MultiDisplayCaptureTests: XCTestCase {
    private func image(width: Int, height: Int, color: CGColor) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    func testCrossDisplaySelectionUsesHigherDensityAndPreservesLayout() throws {
        let left = CapturedDisplay(frame: CGRect(x: -100, y: 0, width: 100, height: 100),
                                   image: try image(width: 100, height: 100, color: NSColor.red.cgColor))
        let right = CapturedDisplay(frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                    image: try image(width: 200, height: 200, color: NSColor.blue.cgColor))
        let rect = MultiDisplayCapture.selection(from: CGPoint(x: 30, y: 80), to: CGPoint(x: -20, y: 20))
        XCTAssertEqual(rect, CGRect(x: -20, y: 20, width: 50, height: 60))
        XCTAssertEqual(MultiDisplayCapture.outputPixelSize(selection: rect, displays: [left, right]), CGSize(width: 100, height: 120))
        let result = try XCTUnwrap(MultiDisplayCapture.render(selection: rect, displays: [left, right]))
        XCTAssertEqual(result.image.width, 100)
        XCTAssertEqual(result.image.height, 120)
        var bytes = [UInt8](repeating: 0, count: 100 * 120 * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: 100, height: 120, bitsPerComponent: 8,
                                              bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(result.image, in: CGRect(x: 0, y: 0, width: 100, height: 120))
        XCTAssertGreaterThan(bytes[(60 * 100 + 10) * 4], 200)
        XCTAssertGreaterThan(bytes[(60 * 100 + 80) * 4 + 2], 200)
    }

    func testSingleDisplayKeepsItsOwnPixelResolution() throws {
        let display = CapturedDisplay(frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                      image: try image(width: 200, height: 200, color: NSColor.red.cgColor))
        let other = CapturedDisplay(frame: CGRect(x: 100, y: 0, width: 100, height: 100),
                                    image: try image(width: 300, height: 300, color: NSColor.blue.cgColor))
        let selection = CGRect(x: 10, y: 10, width: 20, height: 30)
        let result = try XCTUnwrap(MultiDisplayCapture.render(selection: selection, displays: [display, other]))
        XCTAssertEqual(result.image.width, 40)
        XCTAssertEqual(result.image.height, 60)
        XCTAssertEqual(MultiDisplayCapture.outputPixelSize(selection: selection, displays: [display, other]), CGSize(width: 40, height: 60))
        XCTAssertEqual(MultiDisplayCapture.localRect(CGRect(x: 0, y: 70, width: 20, height: 20), in: display.frame),
                       CGRect(x: 0, y: 10, width: 20, height: 20))
    }
}
