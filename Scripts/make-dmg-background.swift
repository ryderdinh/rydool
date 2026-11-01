import AppKit

guard CommandLine.arguments.count == 2,
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 380,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
      let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Usage: make-dmg-background.swift output.png")
}
bitmap.size = NSSize(width: 640, height: 380)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func text(_ value: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, tint: NSColor) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    (value as NSString).draw(in: NSRect(x: 0, y: y, width: 640, height: size + 10),
                             withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                              .foregroundColor: tint, .paragraphStyle: style])
}

let canvas = NSRect(x: 0, y: 0, width: 640, height: 380)
NSGradient(starting: color(0.96, 0.97, 1), ending: color(0.88, 0.91, 0.98))?.draw(in: canvas, angle: -90)
color(1, 1, 1, 0.50).setFill()
NSBezierPath(roundedRect: NSRect(x: 52, y: 77, width: 536, height: 173), xRadius: 26, yRadius: 26).fill()
text("Welcome to Rydool", y: 311, size: 27, weight: .semibold, tint: color(0.13, 0.16, 0.27))
text("A little more room to think.", y: 283, size: 13, weight: .regular, tint: color(0.41, 0.45, 0.56))
text("DRAG RYDOOL TO APPLICATIONS", y: 30, size: 11, weight: .semibold, tint: color(0.40, 0.44, 0.56))

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 286, y: 175))
arrow.line(to: NSPoint(x: 348, y: 175))
arrow.move(to: NSPoint(x: 339, y: 184))
arrow.line(to: NSPoint(x: 348, y: 175))
arrow.line(to: NSPoint(x: 339, y: 166))
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
color(0.49, 0.56, 0.74).setStroke()
arrow.stroke()

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode PNG") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
