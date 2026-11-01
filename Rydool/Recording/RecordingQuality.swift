import CoreGraphics

enum RecordingResolution: String, CaseIterable, Identifiable {
    case native, hd1080, hd720
    var id: String { rawValue }
    var title: String {
        switch self {
        case .native: L("Original")
        case .hd1080: "1080p"
        case .hd720: "720p"
        }
    }
    var maxSize: CGSize? {
        switch self {
        case .native: nil
        case .hd1080: CGSize(width: 1920, height: 1080)
        case .hd720: CGSize(width: 1280, height: 720)
        }
    }
}

enum RecordingFrameRate: Int, CaseIterable, Identifiable {
    case fps30 = 30, fps60 = 60
    var id: Int { rawValue }
    var title: String { "\(rawValue) FPS" }
}

enum RecordingBitrate: String, CaseIterable, Identifiable {
    case compact, balanced, high
    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: L("Smaller file")
        case .balanced: L("Balanced")
        case .high: L("Higher quality")
        }
    }
    func bitsPerSecond(width: Int, height: Int, frameRate: RecordingFrameRate) -> Int {
        let multiplier: Double
        let maximum: Double
        switch self {
        case .compact: (multiplier, maximum) = (3, 12_000_000)
        case .balanced: (multiplier, maximum) = (5, 20_000_000)
        case .high: (multiplier, maximum) = (8, 40_000_000)
        }
        let estimate = Double(width) * Double(height) * multiplier * Double(frameRate.rawValue) / 60
        return Int(min(maximum, max(2_000_000, estimate)))
    }
}
