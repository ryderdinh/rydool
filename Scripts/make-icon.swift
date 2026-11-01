import AppKit

/// Vector artwork created for Rydool. Coordinates use a 1024-point canvas.
private enum RydoolIconArtwork {
    static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static func rounded(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    static func draw() {
        // Leave the standard macOS icon-grid margin around the rounded tile.
        let tile = rounded(NSRect(x: 100, y: 100, width: 824, height: 824), radius: 185)
        let tileShadow = NSShadow()
        tileShadow.shadowColor = color(0.02, 0.03, 0.10, 0.36)
        tileShadow.shadowBlurRadius = 28
        tileShadow.shadowOffset = NSSize(width: 0, height: -12)
        NSGraphicsContext.saveGraphicsState()
        tileShadow.set()
        color(0.10, 0.11, 0.21).setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(starting: color(0.18, 0.20, 0.31), ending: color(0.07, 0.08, 0.15))?.draw(in: tile, angle: -90)
        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        let glow = NSGradient(colorsAndLocations:
            (color(0.47, 0.53, 0.76, 0.18), 0),
            (color(0.30, 0.34, 0.60, 0), 1))
        glow?.draw(fromCenter: NSPoint(x: 260, y: 895), radius: 0,
                   toCenter: NSPoint(x: 260, y: 895), radius: 730, options: [])
        NSGraphicsContext.restoreGraphicsState()

        // A continuous, diagonally woven loop is Rydool's abstract mark.
        let ribbon = CGMutablePath()
        ribbon.move(to: CGPoint(x: 512, y: 512))
        ribbon.addCurve(to: CGPoint(x: 330, y: 680), control1: CGPoint(x: 452, y: 580), control2: CGPoint(x: 404, y: 680))
        ribbon.addCurve(to: CGPoint(x: 242, y: 560), control1: CGPoint(x: 270, y: 680), control2: CGPoint(x: 242, y: 628))
        ribbon.addCurve(to: CGPoint(x: 330, y: 414), control1: CGPoint(x: 242, y: 477), control2: CGPoint(x: 269, y: 414))
        ribbon.addCurve(to: CGPoint(x: 512, y: 512), control1: CGPoint(x: 405, y: 414), control2: CGPoint(x: 457, y: 462))
        ribbon.addCurve(to: CGPoint(x: 694, y: 610), control1: CGPoint(x: 567, y: 562), control2: CGPoint(x: 619, y: 610))
        ribbon.addCurve(to: CGPoint(x: 782, y: 464), control1: CGPoint(x: 755, y: 610), control2: CGPoint(x: 782, y: 547))
        ribbon.addCurve(to: CGPoint(x: 694, y: 344), control1: CGPoint(x: 782, y: 405), control2: CGPoint(x: 754, y: 344))
        ribbon.addCurve(to: CGPoint(x: 512, y: 512), control1: CGPoint(x: 620, y: 344), control2: CGPoint(x: 572, y: 444))
        ribbon.closeSubpath()

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
                          color: color(0.02, 0.03, 0.12, 0.45).cgColor)
        context.addPath(ribbon)
        context.setLineWidth(92)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(color(0.52, 0.78, 1).cgColor)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.addPath(ribbon)
        context.setLineWidth(92)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.replacePathWithStrokedPath()
        context.clip()
        let ribbonGradient = NSGradient(colorsAndLocations:
            (color(0.52, 0.94, 0.91), 0),
            (color(0.49, 0.68, 0.99), 0.52),
            (color(0.76, 0.61, 0.96), 1))
        ribbonGradient?.draw(in: NSRect(x: 170, y: 270, width: 684, height: 484), angle: -25)
        context.restoreGState()

        // Lift one strand at the crossing so the mark reads as a woven ribbon.
        let crossing = CGMutablePath()
        crossing.move(to: CGPoint(x: 330, y: 414))
        crossing.addCurve(to: CGPoint(x: 512, y: 512),
                          control1: CGPoint(x: 405, y: 414), control2: CGPoint(x: 457, y: 462))
        crossing.addCurve(to: CGPoint(x: 694, y: 610),
                          control1: CGPoint(x: 567, y: 562), control2: CGPoint(x: 619, y: 610))
        context.saveGState()
        context.clip(to: CGRect(x: 415, y: 415, width: 194, height: 194))
        context.setShadow(offset: CGSize(width: -5, height: -7), blur: 13,
                          color: color(0.02, 0.03, 0.12, 0.45).cgColor)
        context.addPath(crossing)
        context.setLineWidth(92)
        context.setLineCap(.butt)
        context.setStrokeColor(color(0.49, 0.68, 0.99).cgColor)
        context.strokePath()
        context.restoreGState()
        context.saveGState()
        context.addPath(crossing)
        context.setLineWidth(92)
        context.setLineCap(.butt)
        context.replacePathWithStrokedPath()
        context.clip()
        ribbonGradient?.draw(in: NSRect(x: 170, y: 270, width: 684, height: 484), angle: -25)
        context.restoreGState()
    }
}

/// Produces all sizes required by iconutil from the same vector artwork.
private struct IconSetWriter {
    let directory: URL
    private let sizes = [16, 32, 128, 256, 512]

    func write() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in sizes {
            for scale in [1, 2] {
                let suffix = scale == 2 ? "@2x" : ""
                let filename = "icon_\(points)x\(points)\(suffix).png"
                let png = try render(pixels: points * scale)
                try png.write(to: directory.appendingPathComponent(filename), options: .atomic)
            }
        }
    }

    private func render(pixels: Int) throws -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0) else {
            throw IconError.bitmapCreation(pixels)
        }
        bitmap.size = NSSize(width: 1024, height: 1024)
        guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw IconError.bitmapCreation(pixels)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        RydoolIconArtwork.draw()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw IconError.bitmapCreation(pixels)
        }
        return png
    }
}

private enum IconError: Error { case bitmapCreation(Int) }
let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try IconSetWriter(directory: directory).write()
