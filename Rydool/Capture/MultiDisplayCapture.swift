import AppKit

/// A captured display in AppKit's global, bottom-left-origin coordinate space.
struct CapturedDisplay {
    let frame: CGRect
    let image: CGImage
}

enum MultiDisplayCapture {
    static func selection(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y).standardized
    }

    static func localRect(_ globalRect: CGRect, in frame: CGRect) -> CGRect? {
        let part = globalRect.intersection(frame)
        guard !part.isNull, !part.isEmpty else { return nil }
        return CGRect(x: part.minX - frame.minX, y: frame.maxY - part.maxY,
                      width: part.width, height: part.height)
    }

    static func outputPixelSize(selection: CGRect, displays: [CapturedDisplay]) -> CGSize? {
        let participating = displays.filter { !$0.frame.intersection(selection).isEmpty }
        guard !participating.isEmpty, !selection.isEmpty else { return nil }
        if participating.count == 1, let display = participating.first,
           let local = localRect(selection, in: display.frame),
           let mapping = PixelMapping(imageSize: CGSize(width: display.image.width, height: display.image.height),
                                      viewSize: display.frame.size, selection: local) {
            return mapping.crop.size
        }
        let scale = participating.map { max(CGFloat($0.image.width) / $0.frame.width,
                                            CGFloat($0.image.height) / $0.frame.height) }.max() ?? 1
        return CGSize(width: ceil(selection.width * scale), height: ceil(selection.height * scale))
    }

    static func render(selection: CGRect, displays: [CapturedDisplay]) -> RenderedScreenshot? {
        let participating = displays.filter { !$0.frame.intersection(selection).isEmpty }
        guard !participating.isEmpty, !selection.isEmpty else { return nil }
        if participating.count == 1, let display = participating.first,
           let local = localRect(selection, in: display.frame) {
            return ScreenshotRenderer.render(image: display.image, viewSize: display.frame.size,
                                             selection: local, annotations: [])
        }
        let scale = participating.map { max(CGFloat($0.image.width) / $0.frame.width,
                                            CGFloat($0.image.height) / $0.frame.height) }.max() ?? 1
        let width = Int(ceil(selection.width * scale))
        let height = Int(ceil(selection.height * scale))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        for display in participating {
            let frame = display.frame
            let destination = CGRect(x: (frame.minX - selection.minX) * scale,
                                     y: (frame.minY - selection.minY) * scale,
                                     width: frame.width * scale, height: frame.height * scale)
            context.draw(display.image, in: destination)
        }
        guard let image = context.makeImage() else { return nil }
        return RenderedScreenshot(image: image, pointSize: selection.size)
    }
}
