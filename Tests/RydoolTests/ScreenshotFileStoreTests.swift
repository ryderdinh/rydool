import AppKit
import XCTest
@testable import Rydool

final class ScreenshotFileStoreTests: XCTestCase {
    func testSavePNGAndChooseDistinctNames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 12, height: 8, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let screenshot = RenderedScreenshot(image: try XCTUnwrap(context.makeImage()), pointSize: CGSize(width: 12, height: 8))
        let store = ScreenshotFileStore()
        let first = store.availableURL(in: directory, named: "capture.png")
        try store.save(screenshot, to: first)
        let second = store.availableURL(in: directory, named: "capture.png")
        XCTAssertEqual(second.lastPathComponent, "capture (2).png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: first)))
        XCTAssertEqual(bitmap.pixelsWide, 12)
        XCTAssertEqual(bitmap.pixelsHigh, 8)
        XCTAssertThrowsError(try store.save(screenshot, to: directory.appendingPathComponent("missing/capture.png"))) { error in
            guard case ImageExportFailure.writeFailed = error else { return XCTFail("Expected a write failure") }
        }
    }
}
