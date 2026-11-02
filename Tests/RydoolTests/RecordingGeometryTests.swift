import XCTest
@testable import Rydool

final class RecordingGeometryTests: XCTestCase {
    func testMapsSelectionOnOffsetRetinaDisplayToTopLeftCoordinates() throws {
        let geometry = try XCTUnwrap(RecordingGeometry(
            screenFrame: CGRect(x: -1440, y: 200, width: 1440, height: 900),
            selection: CGRect(x: -1340, y: 700, width: 301, height: 201), scale: 2))
        XCTAssertEqual(geometry.sourceRect, CGRect(x: 100, y: 199, width: 301, height: 201))
        XCTAssertEqual(geometry.pixelWidth, 602)
        XCTAssertEqual(geometry.pixelHeight, 402)
    }

    func testClipsToDisplayAndRoundsEncoderSizeDownToEvenPixels() throws {
        let geometry = try XCTUnwrap(RecordingGeometry(
            screenFrame: CGRect(x: 100, y: 50, width: 200, height: 100),
            selection: CGRect(x: 90, y: 60, width: 113, height: 35), scale: 1))
        XCTAssertEqual(geometry.sourceRect, CGRect(x: 0, y: 55, width: 103, height: 35))
        XCTAssertEqual(geometry.pixelWidth, 102)
        XCTAssertEqual(geometry.pixelHeight, 34)
    }

    func testResolutionPreservesAspectRatioWithoutUpscaling() throws {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let full = try XCTUnwrap(RecordingGeometry(screenFrame: frame, selection: frame, scale: 2, resolution: .hd1080))
        XCTAssertEqual(full.pixelWidth, 1920)
        XCTAssertEqual(full.pixelHeight, 1080)
        XCTAssertEqual(full.sourceRect.size, frame.size)
        let small = try XCTUnwrap(RecordingGeometry(screenFrame: frame, selection: CGRect(x: 0, y: 0, width: 300, height: 200), scale: 1, resolution: .hd720))
        XCTAssertEqual(small.pixelWidth, 300)
        XCTAssertEqual(small.pixelHeight, 200)
        let portrait = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        let rotated = try XCTUnwrap(RecordingGeometry(screenFrame: portrait, selection: portrait, scale: 2, resolution: .hd720))
        XCTAssertEqual(rotated.pixelWidth, 720)
        XCTAssertEqual(rotated.pixelHeight, 1280)
    }

    func testBitrateRespondsToQualityAndFrameRate() {
        let compact = RecordingBitrate.compact.bitsPerSecond(width: 1920, height: 1080, frameRate: .fps60)
        let balanced = RecordingBitrate.balanced.bitsPerSecond(width: 1920, height: 1080, frameRate: .fps60)
        let high = RecordingBitrate.high.bitsPerSecond(width: 1920, height: 1080, frameRate: .fps60)
        XCTAssertLessThan(compact, balanced)
        XCTAssertLessThan(balanced, high)
        XCTAssertLessThan(RecordingBitrate.balanced.bitsPerSecond(width: 1920, height: 1080, frameRate: .fps30), balanced)
    }

    func testRejectsEmptyInvalidAndOversizedSelections() {
        let screen = CGRect(x: 0, y: 0, width: 20000, height: 100)
        XCTAssertNil(RecordingGeometry(screenFrame: screen, selection: .zero, scale: 1))
        XCTAssertNil(RecordingGeometry(screenFrame: screen, selection: screen, scale: 1))
        XCTAssertNil(RecordingGeometry(screenFrame: screen, selection: CGRect(x: 0, y: 0, width: 10, height: 10), scale: .nan))
        XCTAssertNil(RecordingGeometry(screenFrame: screen, selection: CGRect(x: 21000, y: 0, width: 10, height: 10), scale: 1))
    }
}
