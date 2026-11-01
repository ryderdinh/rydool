import AppKit
import XCTest
@testable import Rydool

final class AnnotationRenderingTests: XCTestCase {
    private func canvas() throws -> CGContext {
        try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
                                bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    }

    private func alpha(_ context: CGContext, x: Int, y: Int) throws -> UInt8 {
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let row = context.height - 1 - y
        return data[row * context.bytesPerRow + x * 4 + 3]
    }

    func testArrowDrawsHeadAndShaftInBothDirections() throws {
        let style = MarkAppearance(color: .red, lineWidth: 4, fontSize: 18)
        for (tail, tip) in [(CGPoint(x: 20, y: 50), CGPoint(x: 80, y: 50)),
                            (CGPoint(x: 80, y: 50), CGPoint(x: 20, y: 50))] {
            let context = try canvas()
            ArrowMark(start: tail, end: tip, style: style).draw(in: context)
            XCTAssertGreaterThan(try alpha(context, x: 50, y: 50), 0)
            let baseX = tip.x > tail.x ? 68 : 32
            XCTAssertGreaterThan(try alpha(context, x: baseX, y: 55), 0)
            XCTAssertEqual(try alpha(context, x: 50, y: 20), 0)
        }
    }

    func testPenDrawsDotAndContinuousStroke() throws {
        let style = MarkAppearance(color: .blue, lineWidth: 4, fontSize: 18)
        var pen = FreehandMark(start: CGPoint(x: 20, y: 20), style: style)
        let dot = try canvas()
        pen.draw(in: dot)
        XCTAssertGreaterThan(try alpha(dot, x: 20, y: 20), 0)
        pen.add(CGPoint(x: 20.1, y: 20.1))
        XCTAssertEqual(pen.points.count, 1)
        pen.add(CGPoint(x: 40, y: 30))
        pen.add(CGPoint(x: 60, y: 20))
        let stroke = try canvas()
        pen.draw(in: stroke)
        XCTAssertGreaterThan(try alpha(stroke, x: 40, y: 30), 0)
    }

    func testRectangleNormalizesAllDragDirections() {
        let style = MarkAppearance(color: .green, lineWidth: 2, fontSize: 16)
        let shape = BoxMark(start: CGPoint(x: 40, y: 30),
                                        end: CGPoint(x: 10, y: 5), style: style)
        XCTAssertEqual(shape.rect, CGRect(x: 10, y: 5, width: 30, height: 25))
        XCTAssertFalse(shape.isEmpty)
    }

    func testToolMetadataAndWeightCycleRemainStable() {
        XCTAssertEqual(AnnotationTool.allCases.map(\.key), ["p", "a", "r", "t"])
        XCTAssertEqual(LineWeight.thin.next, .medium)
        XCTAssertEqual(LineWeight.medium.next, .thick)
        XCTAssertEqual(LineWeight.thick.next, .thin)
        XCTAssertEqual(LineWeight.medium.lineWidth, 4)
        XCTAssertEqual(LineWeight.medium.fontSize, 22)
    }

    func testInlineTextGrowsForUnicodeAndAdditionalLines() {
        let style = MarkAppearance(color: .blue, lineWidth: 4, fontSize: 18)
        let field = InlineTextEditor(style: style)
        field.stringValue = "A"
        field.fitToText()
        let oneLine = field.frame.size
        field.stringValue = "Tiếng Việt 漢字\n"
        field.fitToText()
        XCTAssertGreaterThan(field.frame.width, oneLine.width)
        XCTAssertGreaterThan(field.frame.height, oneLine.height)
        XCTAssertTrue(TextMark(text: " \n ", origin: .zero, style: style).isEmpty)
        XCTAssertFalse(TextMark(text: "Tiếng Việt", origin: .zero, style: style).isEmpty)
    }

    func testAnnotationUsesSelectionOffsetAtRetinaScale() throws {
        let background = try canvas()
        background.setFillColor(NSColor.white.cgColor)
        background.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let source = try XCTUnwrap(background.makeImage())
        let style = MarkAppearance(color: .red, lineWidth: 3, fontSize: 18)
        let mark = BoxMark(start: CGPoint(x: 15, y: 15),
                                       end: CGPoint(x: 30, y: 25), style: style)
        let output = try XCTUnwrap(ScreenshotRenderer.render(
            image: source, viewSize: CGSize(width: 50, height: 50),
            selection: CGRect(x: 10, y: 10, width: 30, height: 25), annotations: [mark]))
        let bitmap = NSBitmapImageRep(cgImage: output.image)
        let stroke = try XCTUnwrap(bitmap.colorAt(x: 10, y: 20)?.usingColorSpace(.deviceRGB))
        let untouched = try XCTUnwrap(bitmap.colorAt(x: 50, y: 20)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(stroke.redComponent, stroke.greenComponent + 0.5)
        XCTAssertGreaterThan(untouched.greenComponent, 0.9)
    }
}
