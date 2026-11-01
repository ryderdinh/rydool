import AppKit

/// A screenshot in backing pixels, with its logical size retained for pasteboard output.
struct RenderedScreenshot {
    let image: CGImage
    let pointSize: CGSize

    func pngData() -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = pointSize
        return bitmap.representation(using: .png, properties: [:])
    }
}

/// Maps a rectangular selection from overlay points to source image pixels.
private struct PixelMapping {
    let xScale: CGFloat
    let yScale: CGFloat
    let crop: CGRect

    init?(imageSize: CGSize, viewSize: CGSize, selection: CGRect) {
        let numbers = [viewSize.width, viewSize.height, selection.origin.x,
                       selection.origin.y, selection.width, selection.height]
        guard numbers.allSatisfy(\.isFinite), viewSize.width > 0, viewSize.height > 0 else { return nil }
        xScale = imageSize.width / viewSize.width
        yScale = imageSize.height / viewSize.height
        let transform = CGAffineTransform(scaleX: xScale, y: yScale)
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        crop = selection.applying(transform).integral.intersection(imageBounds)
        guard !crop.isEmpty, !crop.isNull else { return nil }
    }

    var logicalSize: CGSize { CGSize(width: crop.width / xScale, height: crop.height / yScale) }

    func prepareAnnotationCoordinates(in context: CGContext) {
        context.translateBy(x: -crop.minX, y: crop.height + crop.minY)
        context.scaleBy(x: xScale, y: -yScale)
    }
}

enum ScreenshotRenderer {
    static func render(image: CGImage, viewSize: CGSize, selection: CGRect,
                       annotations: [DrawableMark]) -> RenderedScreenshot? {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard let mapping = PixelMapping(imageSize: imageSize, viewSize: viewSize, selection: selection),
              let base = image.cropping(to: mapping.crop) else { return nil }
        guard !annotations.isEmpty else {
            return RenderedScreenshot(image: base, pointSize: mapping.logicalSize)
        }

        let rgb = base.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapFlags = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let drawing = CGContext(data: nil, width: base.width, height: base.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: rgb, bitmapInfo: bitmapFlags) else { return nil }
        drawing.interpolationQuality = .none
        drawing.draw(base, in: CGRect(origin: .zero, size: CGSize(width: base.width, height: base.height)))
        mapping.prepareAnnotationCoordinates(in: drawing)
        drawing.setShouldAntialias(true)
        annotations.forEach { $0.draw(in: drawing) }
        guard let output = drawing.makeImage() else { return nil }
        return RenderedScreenshot(image: output, pointSize: mapping.logicalSize)
    }
}
