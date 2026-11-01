import AVFoundation

/// MP4 players often select just one audio track, so combine both sources when needed.
enum RecordingAudioMixer {
    enum MixError: LocalizedError {
        case cannotExport, exportFailed(String)
        var errorDescription: String? {
            switch self {
            case .cannotExport: return "Cannot combine the recording audio."
            case .exportFailed(let detail): return detail
            }
        }
    }

    static func mixIfNeeded(at url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.count > 1 else { return }
        let composition = AVMutableComposition()
        let duration = try await asset.load(.duration)
        let fullRange = CMTimeRange(start: .zero, duration: duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let video = videoTracks.first,
              let targetVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw MixError.cannotExport }
        try targetVideo.insertTimeRange(fullRange, of: video, at: .zero)
        targetVideo.preferredTransform = try await video.load(.preferredTransform)
        var parameters: [AVAudioMixInputParameters] = []
        for source in audioTracks {
            guard let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw MixError.cannotExport }
            let range = try await source.load(.timeRange).intersection(fullRange)
            guard !range.isEmpty else { continue }
            try target.insertTimeRange(range, of: source, at: range.start)
            let input = AVMutableAudioMixInputParameters(track: target)
            input.setVolume(0.5, at: .zero)
            parameters.append(input)
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw MixError.cannotExport }
        let mixed = url.deletingLastPathComponent().appendingPathComponent("Rydool-mix-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: mixed) }
        export.outputURL = mixed
        export.outputFileType = .mp4
        export.audioMix = audioMix
        await export.export()
        guard export.status == .completed else { throw MixError.exportFailed(export.error?.localizedDescription ?? "Cannot combine the recording audio.") }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: mixed)
    }
}
