import AppKit

/// Draws the Rydool mark as a system-tinted template and animates it on activation.
final class StatusItemAnimator {
    private weak var button: NSStatusBarButton?
    private var timer: Timer?
    private static let frames: [NSImage] = [
        (0.0, 1.0), (-5.0, 0.96), (-8.0, 0.95), (-4.0, 0.98),
        (3.0, 1.02), (2.0, 1.01), (0.0, 1.0)
    ].map { image(angle: $0.0, scale: $0.1) }

    init(button: NSStatusBarButton) {
        self.button = button
        button.image = Self.frames[0]
    }

    func play() {
        timer?.invalidate()
        timer = nil
        guard let button else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            button.image = Self.frames[0]
            return
        }
        var index = 1
        button.image = Self.frames[index]
        let next = Timer(timeInterval: 0.04, repeats: true) { [weak self] timer in
            guard let self, let button = self.button else { timer.invalidate(); return }
            index += 1
            button.image = Self.frames[index]
            if index == Self.frames.count - 1 {
                timer.invalidate()
                self.timer = nil
            }
        }
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }

    private static func image(angle: CGFloat, scale: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            context.translateBy(x: 9, y: 9)
            context.rotate(by: angle * .pi / 180)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -9, y: -9)
            NSColor.black.setStroke()
            let mark = NSBezierPath()
            mark.lineCapStyle = .round
            mark.lineJoinStyle = .round
            mark.move(to: NSPoint(x: 512, y: 512))
            mark.curve(to: NSPoint(x: 330, y: 680), controlPoint1: NSPoint(x: 452, y: 580), controlPoint2: NSPoint(x: 404, y: 680))
            mark.curve(to: NSPoint(x: 242, y: 560), controlPoint1: NSPoint(x: 270, y: 680), controlPoint2: NSPoint(x: 242, y: 628))
            mark.curve(to: NSPoint(x: 330, y: 414), controlPoint1: NSPoint(x: 242, y: 477), controlPoint2: NSPoint(x: 269, y: 414))
            mark.curve(to: NSPoint(x: 512, y: 512), controlPoint1: NSPoint(x: 405, y: 414), controlPoint2: NSPoint(x: 457, y: 462))
            mark.curve(to: NSPoint(x: 694, y: 610), controlPoint1: NSPoint(x: 567, y: 562), controlPoint2: NSPoint(x: 619, y: 610))
            mark.curve(to: NSPoint(x: 782, y: 464), controlPoint1: NSPoint(x: 755, y: 610), controlPoint2: NSPoint(x: 782, y: 547))
            mark.curve(to: NSPoint(x: 694, y: 344), controlPoint1: NSPoint(x: 782, y: 405), controlPoint2: NSPoint(x: 754, y: 344))
            mark.curve(to: NSPoint(x: 512, y: 512), controlPoint1: NSPoint(x: 620, y: 344), controlPoint2: NSPoint(x: 572, y: 444))
            mark.close()
            mark.transform(using: AffineTransform(m11: 0.022, m12: 0, m21: 0, m22: 0.022, tX: -2.264, tY: -2.264))
            mark.lineWidth = 2.024
            mark.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
