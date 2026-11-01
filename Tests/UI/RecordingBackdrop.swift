import AppKit

final class Backdrop: NSView {
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
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { exit(1) }
let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
window.contentView = Backdrop(frame: CGRect(origin: .zero, size: screen.frame.size))
window.isReleasedWhenClosed = false
window.level = .normal
window.orderFrontRegardless()
app.run()
