import AppKit
import AVFoundation
import ScreenCaptureKit

/// Owns one ScreenCaptureKit stream and its optional microphone capture session.
final class ScreenRecordingStream: NSObject, SCStreamOutput, SCStreamDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum StreamError: LocalizedError {
        case displayUnavailable, microphoneUnavailable
        var errorDescription: String? {
            switch self {
            case .displayUnavailable: return L("The selected display is no longer available.")
            case .microphoneUnavailable: return L("The microphone is unavailable.")
            }
        }
    }

    private let outputURL: URL
    private let combineAudio: Bool
    private let writer: RecordingWriter
    private var stream: SCStream!
    private let microphone: AVCaptureSession?
    private let sampleQueue = DispatchQueue(label: "com.rydool.recording.samples")
    private let microphoneQueue = DispatchQueue(label: "com.rydool.recording.microphone")
    private let onFailure: (Error) -> Void
    private var microphoneObservers: [NSObjectProtocol] = []

    private init(writer: RecordingWriter, outputURL: URL, combineAudio: Bool, filter: SCContentFilter, configuration: SCStreamConfiguration, microphone: AVCaptureSession?, onFailure: @escaping (Error) -> Void) {
        self.writer = writer
        self.outputURL = outputURL
        self.combineAudio = combineAudio
        self.microphone = microphone
        self.onFailure = onFailure
        super.init()
        self.stream = SCStream(filter: filter, configuration: configuration, delegate: self)
    }

    @MainActor
    static func start(displayID: CGDirectDisplayID, geometry: RecordingGeometry, outputURL: URL,
                      systemAudio: Bool, microphone: Bool, frameRate: RecordingFrameRate, bitrate: RecordingBitrate, onFailure: @escaping (Error) -> Void) async throws -> ScreenRecordingStream {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw StreamError.displayUnavailable }
        let config = SCStreamConfiguration()
        config.sourceRect = geometry.sourceRect
        config.width = geometry.pixelWidth
        config.height = geometry.pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate.rawValue))
        config.queueDepth = 5
        config.showsCursor = true
        config.capturesAudio = systemAudio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let micSession: AVCaptureSession?
        if microphone {
            guard let device = AVCaptureDevice.default(for: .audio) else { throw StreamError.microphoneUnavailable }
            let session = AVCaptureSession()
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureAudioDataOutput()
            guard session.canAddInput(input), session.canAddOutput(output) else { throw StreamError.microphoneUnavailable }
            session.addInput(input)
            session.addOutput(output)
            micSession = session
        } else { micSession = nil }
        let writer = try RecordingWriter(url: outputURL, width: geometry.pixelWidth, height: geometry.pixelHeight,
                                         systemAudio: systemAudio, microphone: microphone, frameRate: frameRate, bitrate: bitrate, onFailure: onFailure)
        let recording = ScreenRecordingStream(writer: writer, outputURL: outputURL, combineAudio: systemAudio && microphone, filter: filter, configuration: config, microphone: micSession, onFailure: onFailure)
        let stream = recording.stream!
        if let micSession {
            let center = NotificationCenter.default
            recording.microphoneObservers = [
                center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: micSession, queue: .main) { [weak recording] notification in
                    let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error ?? StreamError.microphoneUnavailable
                    recording?.onFailure(error)
                },
                center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: micSession, queue: .main) { [weak recording] _ in
                    recording?.onFailure(StreamError.microphoneUnavailable)
                }
            ]
        }
        do {
            try stream.addStreamOutput(recording, type: .screen, sampleHandlerQueue: recording.sampleQueue)
            if systemAudio { try stream.addStreamOutput(recording, type: .audio, sampleHandlerQueue: recording.sampleQueue) }
            if let output = micSession?.outputs.first as? AVCaptureAudioDataOutput {
                output.setSampleBufferDelegate(recording, queue: recording.sampleQueue)
            }
            try await stream.startCapture()
            guard await recording.setMicrophoneRunning(true) else { throw StreamError.microphoneUnavailable }
            return recording
        } catch {
            try? await stream.stopCapture()
            writer.cancel()
            throw error
        }
    }

    deinit { microphoneObservers.forEach { NotificationCenter.default.removeObserver($0) } }

    @MainActor
    func stop() async throws {
        microphoneObservers.forEach { NotificationCenter.default.removeObserver($0) }
        microphoneObservers.removeAll()
        let endTime = CMClockGetTime(CMClockGetHostTimeClock())
        _ = await setMicrophoneRunning(false)
        // A stream may already have stopped after an interruption; still finalize the frames received.
        try? await stream.stopCapture()
        try await writer.finish(endTime: endTime)
        if combineAudio { try await RecordingAudioMixer.mixIfNeeded(at: outputURL) }
    }

    private func setMicrophoneRunning(_ running: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            microphoneQueue.async { [self] in
                guard let microphone else { continuation.resume(returning: true); return }
                if running { microphone.startRunning() } else { microphone.stopRunning() }
                continuation.resume(returning: !running || microphone.isRunning)
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
            writer.append(sampleBuffer, track: .video)
        case .audio: writer.append(sampleBuffer, track: .systemAudio)
        default: break
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        writer.append(sampleBuffer, track: .microphone)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [onFailure] in onFailure(error) }
    }
}
