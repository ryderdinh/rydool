import AVFoundation
import CoreMedia

/// Serializes video and optional audio tracks into a single MP4 file.
final class RecordingWriter: @unchecked Sendable {
    enum WriterError: LocalizedError {
        case cannotAddTrack, noVideo, failed(String)
        var errorDescription: String? {
            switch self {
            case .cannotAddTrack: return "Cannot configure the recording tracks."
            case .noVideo: return "No video frames were recorded."
            case .failed(let message): return message
            }
        }
    }

    enum Track { case video, systemAudio, microphone }
    private let queue = DispatchQueue(label: "com.rydool.recording.writer")
    private let videoSlots = DispatchSemaphore(value: 5)
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let systemAudio: AVAssetWriterInput?
    private let microphone: AVAssetWriterInput?
    private var startedAt: CMTime?
    private var stopped = false
    private var firstError: String?

    init(url: URL, width: Int, height: Int, systemAudio: Bool, microphone: Bool) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: min(20_000_000, max(2_000_000, width * height * 5))]
        ])
        self.systemAudio = systemAudio ? Self.audioInput() : nil
        self.microphone = microphone ? Self.audioInput() : nil
        for input in [video, self.systemAudio, self.microphone].compactMap({ $0 }) {
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw WriterError.cannotAddTrack }
            writer.add(input)
        }
        guard writer.startWriting() else { throw WriterError.failed(writer.error?.localizedDescription ?? "Cannot start video writer.") }
    }

    private static func audioInput() -> AVAssetWriterInput {
        AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000
        ])
    }

    func append(_ sample: CMSampleBuffer, track: Track) {
        let isVideo = track == .video
        // Captured frames can be large; drop excess frames instead of growing memory without bound.
        if isVideo && videoSlots.wait(timeout: .now()) != .success { return }
        queue.async { [self] in
            defer { if isVideo { videoSlots.signal() } }
            guard !stopped, CMSampleBufferDataIsReady(sample), writer.status == .writing else { return }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
            guard timestamp.isValid, timestamp.isNumeric else { return }
            if startedAt == nil {
                guard track == .video else { return }
                writer.startSession(atSourceTime: timestamp)
                startedAt = timestamp
            }
            guard let startedAt, timestamp >= startedAt else { return }
            let input: AVAssetWriterInput?
            switch track {
            case .video: input = video
            case .systemAudio: input = systemAudio
            case .microphone: input = microphone
            }
            if let input, input.isReadyForMoreMediaData, !input.append(sample), firstError == nil {
                firstError = writer.error?.localizedDescription ?? "Cannot write recording data."
            }
        }
    }

    func cancel() {
        queue.async { [self] in
            guard !stopped else { return }
            stopped = true
            writer.cancelWriting()
        }
    }

    func finish(endTime: CMTime? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard !stopped else {
                    continuation.resume(throwing: WriterError.failed("Recording has already stopped."))
                    return
                }
                stopped = true
                if let firstError {
                    writer.cancelWriting()
                    continuation.resume(throwing: WriterError.failed(firstError))
                    return
                }
                if writer.status == .failed {
                    continuation.resume(throwing: WriterError.failed(writer.error?.localizedDescription ?? "Cannot write recording data."))
                    return
                }
                guard startedAt != nil else {
                    writer.cancelWriting()
                    continuation.resume(throwing: WriterError.noVideo)
                    return
                }
                if let endTime, let startedAt, endTime.isNumeric, endTime > startedAt {
                    writer.endSession(atSourceTime: endTime)
                }
                [video, systemAudio, microphone].compactMap { $0 }.forEach { $0.markAsFinished() }
                writer.finishWriting { [writer] in
                    if writer.status == .completed { continuation.resume() }
                    else { continuation.resume(throwing: WriterError.failed(writer.error?.localizedDescription ?? "Cannot finish recording.")) }
                }
            }
        }
    }
}
