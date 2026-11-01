import XCTest
import AVFoundation
@testable import Rydool

final class RecordingWriterTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
    }

    private func frame(at index: Int64) throws -> CMSampleBuffer {
        var pixel: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32BGRA,
                                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel), kCVReturnSuccess)
        let image = try XCTUnwrap(pixel)
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image, formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: index, timescale: 30), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image,
                          formatDescription: try XCTUnwrap(format), sampleTiming: &timing, sampleBufferOut: &sample), noErr)
        return try XCTUnwrap(sample)
    }

    private func audio(at offset: Int64, frequency: Double) throws -> CMSampleBuffer {
        let frameCount = 1024
        var asbd = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2,
            mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &format), noErr)
        var pcm = [Int16]()
        for index in 0..<frameCount {
            let value = Int16(8_000 * sin(2 * .pi * frequency * Double(offset + Int64(index)) / 48_000))
            pcm.append(value); pcm.append(value)
        }
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: pcm.count * 2, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: pcm.count * 2, flags: 0, blockBufferOut: &block), noErr)
        let data = try XCTUnwrap(block)
        let status = pcm.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: data, offsetIntoDestination: 0, dataLength: $0.count) }
        XCTAssertEqual(status, noErr)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault,
            dataBuffer: data, formatDescription: try XCTUnwrap(format), sampleCount: frameCount,
            presentationTimeStamp: CMTime(value: offset, timescale: 48_000), packetDescriptions: nil,
            sampleBufferOut: &sample), noErr)
        return try XCTUnwrap(sample)
    }

    func testWritesBothAudioSources() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try RecordingWriter(url: url, width: 64, height: 48, systemAudio: true, microphone: true)
        for index in 0..<30 {
            writer.append(try frame(at: Int64(index)), track: .video)
            let offset = Int64(index * 1024)
            writer.append(try audio(at: offset, frequency: 440), track: .systemAudio)
            writer.append(try audio(at: offset, frequency: 880), track: .microphone)
        }
        try await writer.finish()
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 2)
        try await RecordingAudioMixer.mixIfNeeded(at: url)
        let mixed = AVURLAsset(url: url)
        let mixedTracks = try await mixed.loadTracks(withMediaType: .audio)
        XCTAssertEqual(mixedTracks.count, 1)
        let reader = try AVAssetReader(asset: mixed)
        let audio = AVAssetReaderTrackOutput(track: try XCTUnwrap(mixedTracks.first), outputSettings: [
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
        XCTAssertGreaterThan(samples.count, 10_000)
        for frequency in [440.0, 880.0] {
            let strength = samples.enumerated().reduce(0.0) { sum, pair in
                sum + Double(pair.element) * sin(2 * .pi * frequency * Double(pair.offset) / 44_100)
            }
            XCTAssertGreaterThan(abs(strength) / Double(samples.count), 100, "Missing \(frequency) Hz source")
        }
    }

    func testWritesPlayableVideo() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try RecordingWriter(url: url, width: 64, height: 48, systemAudio: false, microphone: false)
        for index in 0..<20 { writer.append(try frame(at: Int64(index)), track: .video) }
        try await writer.finish()
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0)
    }

    func testStaticScreenRetainsTheFullRecordingDuration() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try RecordingWriter(url: url, width: 64, height: 48, systemAudio: false, microphone: false)
        writer.append(try frame(at: 0), track: .video)
        try await writer.finish(endTime: CMTime(seconds: 3, preferredTimescale: 600))
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThanOrEqual(duration.seconds, 2.9)
    }

    func testFinishWithoutVideoFails() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try RecordingWriter(url: url, width: 64, height: 48, systemAudio: false, microphone: false)
        do {
            try await writer.finish()
            XCTFail("An empty recording must fail")
        } catch RecordingWriter.WriterError.noVideo { }
    }
}
