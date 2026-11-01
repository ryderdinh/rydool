import AppKit
import XCTest
@testable import Rydool

final class ScreenshotPasteboardTests: XCTestCase {
    @MainActor
    func testWritesPNGAndProvidesTIFFWithoutUsingGeneralClipboard() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("rydool-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let generalCount = NSPasteboard.general.changeCount
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        let screenshot = RenderedScreenshot(image: try XCTUnwrap(context.makeImage()),
                                            pointSize: CGSize(width: 10, height: 5))
        var reported: Data?
        try ScreenshotClipboard.copy(screenshot, to: board) { data, _ in reported = data }
        let png = try XCTUnwrap(board.data(forType: .png))
        XCTAssertEqual(png, reported)
        let tiff = try XCTUnwrap(board.data(forType: .tiff))
        let image = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        XCTAssertEqual(image.pixelsWide, 20)
        XCTAssertEqual(image.pixelsHigh, 10)
        XCTAssertEqual(NSPasteboard.general.changeCount, generalCount)
    }
}
