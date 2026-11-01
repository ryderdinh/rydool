import AppKit

final class Backdrop: NSView {
    var tick = 0
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width / 2
        let h = bounds.height / 2
        for (color, rect) in [(NSColor.red, CGRect(x: 0, y: 0, width: w, height: h)),
                              (NSColor.green, CGRect(x: w, y: 0, width: w, height: h)),
                              (NSColor.blue, CGRect(x: 0, y: h, width: w, height: h)),
                              (NSColor.yellow, CGRect(x: w, y: h, width: w, height: h))] {
            color.setFill()
            rect.fill()
        }
        if CommandLine.arguments.contains("--animate") {
            (tick.isMultiple(of: 2) ? NSColor.white : NSColor.black).setFill()
            CGRect(x: 20, y: 20, width: 100, height: 100).fill()
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { exit(1) }
let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
let backdrop = Backdrop(frame: CGRect(origin: .zero, size: screen.frame.size))
window.contentView = backdrop
if CommandLine.arguments.contains("--animate") {
    Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
        backdrop.tick += 1
        backdrop.needsDisplay = true
    }
}
window.isReleasedWhenClosed = false
window.level = .normal
window.orderFrontRegardless()
app.run()
