import AVFoundation
import XCTest
@testable import Rydool

final class RecordingAudioMixerTests: XCTestCase {
    func testCombinesTwoAudioTracksIntoOnePlayableTrack() async throws {
        guard let fixture = ProcessInfo.processInfo.environment["RYDOOL_TEST_AUDIO_FIXTURE"] else {
            throw XCTSkip("Set RYDOOL_TEST_AUDIO_FIXTURE to a video with two audio tracks")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mix-test-\(UUID().uuidString).mp4")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: fixture), to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = AVURLAsset(url: url)
        let originalTracks = try await original.loadTracks(withMediaType: .audio)
        XCTAssertEqual(originalTracks.count, 2)
        try await RecordingAudioMixer.mixIfNeeded(at: url)
        let output = AVURLAsset(url: url)
        let tracks = try await output.loadTracks(withMediaType: .audio)
        let videos = try await output.loadTracks(withMediaType: .video)
        let duration = try await output.load(.duration)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(videos.count, 1)
        XCTAssertGreaterThan(duration.seconds, 0.5)
        let reader = try AVAssetReader(asset: output)
        let audio = AVAssetReaderTrackOutput(track: try XCTUnwrap(tracks.first), outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
        ])
        XCTAssertTrue(reader.canAdd(audio))
        reader.add(audio)
        XCTAssertTrue(reader.startReading())
        var samples: [Int16] = []
        while let buffer = audio.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            var data = Data(count: CMBlockBufferGetDataLength(block))
            let result = data.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: bytes.baseAddress!)
            }
            XCTAssertEqual(result, noErr)
            data.withUnsafeBytes { bytes in
                for index in stride(from: 0, to: bytes.count - 1, by: 2) {
                    let value = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
                    samples.append(Int16(bitPattern: value))
                }
            }
        }
        XCTAssertGreaterThan(samples.count, 20_000)
        for frequency in [440.0, 880.0] {
            let strength = samples.enumerated().reduce(0.0) { sum, pair in
                sum + Double(pair.element) * sin(2 * .pi * frequency * Double(pair.offset) / 44_100)
            }
            XCTAssertGreaterThan(abs(strength) / Double(samples.count), 100, "Missing \(frequency) Hz source")
        }
    }
}
