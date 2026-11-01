import CoreGraphics

/// Converts an AppKit screen selection into ScreenCaptureKit display-local coordinates.
struct RecordingGeometry: Equatable {
    let sourceRect: CGRect
    let pixelWidth: Int
    let pixelHeight: Int

    init?(screenFrame: CGRect, selection: CGRect, scale: CGFloat) {
        let values = [screenFrame.minX, screenFrame.minY, screenFrame.width, screenFrame.height,
                      selection.minX, selection.minY, selection.width, selection.height, scale]
        guard values.allSatisfy(\.isFinite), screenFrame.width > 0, screenFrame.height > 0,
              selection.width > 0, selection.height > 0, scale > 0 else { return nil }
        let area = selection.intersection(screenFrame)
        guard !area.isNull, area.width > 0, area.height > 0 else { return nil }
        let width = (area.width * scale).rounded(.down)
        let height = (area.height * scale).rounded(.down)
        // H.264 encoders require even dimensions. Reject unreasonably large input before conversion.
        guard width >= 2, height >= 2, width <= 16384, height <= 16384 else { return nil }
        pixelWidth = Int(width) & ~1
        pixelHeight = Int(height) & ~1
        sourceRect = CGRect(x: area.minX - screenFrame.minX,
                            y: screenFrame.maxY - area.maxY,
                            width: area.width, height: area.height)
    }
}
