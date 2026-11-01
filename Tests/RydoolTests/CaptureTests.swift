import XCTest
import AppKit
@testable import Rydool

final class CaptureTests: XCTestCase {
    func testSelectionClampsToDisplay() {
        var selection = SelectionManager(bounds: CGRect(x: 0, y: 0, width: 100, height: 80))
        selection.set(CGRect(x: -10, y: 20, width: 150, height: 100))
        XCTAssertEqual(selection.rect, CGRect(x: 0, y: 20, width: 100, height: 60))
    }

    func testRetinaCropAndPNGDimensions() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 120, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
        let image = try XCTUnwrap(context.makeImage())
        let rendered = try XCTUnwrap(ScreenshotRenderer.render(image: image, viewSize: CGSize(width: 100, height: 60), selection: CGRect(x: 5, y: 10, width: 40, height: 25), annotations: []))
        XCTAssertEqual(rendered.image.width, 80)
        XCTAssertEqual(rendered.image.height, 50)
        let png = try XCTUnwrap(rendered.pngData())
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(decoded.pixelsWide, 80)
        XCTAssertEqual(decoded.pixelsHigh, 50)
    }
    func testAnnotationsRenderAndUndo() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 120, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
        let image = try XCTUnwrap(context.makeImage())
        let style = MarkAppearance(color: .red, lineWidth: 3, fontSize: 14)
        let rectangle = BoxMark(start: CGPoint(x: 5, y: 5), end: CGPoint(x: 35, y: 25), style: style)
        let text = TextMark(text: "Tiếng Việt\nDòng hai", origin: CGPoint(x: 8, y: 28), style: style)
        let size = CGSize(width: 100, height: 60)
        let selection = CGRect(origin: .zero, size: size)
        let plain = try XCTUnwrap(ScreenshotRenderer.render(image: image, viewSize: size, selection: selection, annotations: [])?.pngData())
        let marked = try XCTUnwrap(ScreenshotRenderer.render(image: image, viewSize: size, selection: selection, annotations: [rectangle, text])?.pngData())
        XCTAssertNotEqual(marked, plain)
        let canvas = MarkupCanvas(frame: CGRect(origin: .zero, size: size))
        canvas.add(rectangle); canvas.add(text)
        XCTAssertEqual(canvas.annotations.count, 2)
        XCTAssertTrue(canvas.undo()); XCTAssertEqual(canvas.annotations.count, 1)
        XCTAssertTrue(canvas.undo()); XCTAssertFalse(canvas.undo())
    }

    @MainActor func testFullScreenOverlayCanRenderSyntheticImage() throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 120, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let overlay = SelectionCanvas(frame: CGRect(x: 0, y: 0, width: 100, height: 60), image: image, toolState: MarkupSession())
        XCTAssertFalse(overlay.hasSelection)
        overlay.selectFullScreen()
        XCTAssertTrue(overlay.hasSelection)
        let result = try XCTUnwrap(overlay.renderScreenshot())
        XCTAssertEqual(result.image.width, 200)
        XCTAssertEqual(result.image.height, 120)
    }

    @MainActor func testRegionSelectionThroughSyntheticMouseEvents() throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 120, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 60), styleMask: [.borderless], backing: .buffered, defer: false)
        let overlay = SelectionCanvas(frame: CGRect(x: 0, y: 0, width: 100, height: 60), image: image, toolState: MarkupSession())
        window.contentView = overlay
        func event(_ type: NSEvent.EventType, _ local: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: overlay.convert(local, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        overlay.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 10, y: 10)))
        overlay.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 60, y: 40)))
        overlay.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 60, y: 40)))
        let rendered = try XCTUnwrap(overlay.renderScreenshot())
        XCTAssertEqual(rendered.image.width, 100)
        XCTAssertEqual(rendered.image.height, 60)
    }

    func testDifferentSyntheticDisplayScalesAndEdges() throws {
        for scale in [1, 2] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 100 * scale, height: 80 * scale, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let image = try XCTUnwrap(context.makeImage())
            let result = try XCTUnwrap(ScreenshotRenderer.render(image: image, viewSize: CGSize(width: 100, height: 80), selection: CGRect(x: 80, y: 60, width: 30, height: 30), annotations: []))
            XCTAssertEqual(result.image.width, 20 * scale)
            XCTAssertEqual(result.image.height, 20 * scale)
        }
    }

}
