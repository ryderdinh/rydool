import AppKit
import ApplicationServices
import Foundation

let app = AXUIElementCreateApplication(pid_t(Int32(CommandLine.arguments[1])!))
let targetPID = pid_t(Int32(CommandLine.arguments[2])!)
let board = NSPasteboard(name: NSPasteboard.Name(CommandLine.arguments[3]))
let resultFile = CommandLine.arguments[4]
func fail(_ message: String) -> Never { fputs("FAIL: \(message)\n", stderr); exit(1) }
func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}
func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? [] }
func find(_ element: AXUIElement, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
    if match(element) { return element }
    for child in children(element) { if let found = find(child, match) { return found } }
    return nil
}
func contains(_ element: AXUIElement, _ value: String) -> Bool {
    [kAXTitleAttribute as String, kAXDescriptionAttribute as String, kAXValueAttribute as String]
        .compactMap { attribute(element, $0) as? String }.contains { $0.contains(value) }
}
func wait(_ body: () -> AXUIElement?) -> AXUIElement? {
    for _ in 0..<40 { if let found = body() { return found }; Thread.sleep(forTimeInterval: 0.1) }
    return nil
}
func press(_ element: AXUIElement) {
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { fail("Cannot press control") }
}
func click(_ element: AXUIElement) {
    guard let rawPosition = attribute(element, kAXPositionAttribute as String),
          let rawSize = attribute(element, kAXSizeAttribute as String),
          CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() else { fail("Control has no screen position") }
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position), AXValueGetValue(rawSize as! AXValue, .cgSize, &size) else { fail("Cannot read control position") }
    let point = CGPoint(x: position.x + min(size.width / 2, 40), y: position.y + size.height / 2)
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { fail("Cannot create click") }
    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
}
func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { fail("Cannot create key event") }
    down.flags = flags; up.flags = flags
    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
}
guard AXIsProcessTrusted(), let target = NSRunningApplication(processIdentifier: targetPID) else { fail("Test target or accessibility unavailable") }
let sample = "Rydool paste fixture"
board.clearContents(); guard board.setString(sample, forType: .string) else { fail("Cannot seed isolated clipboard") }
Thread.sleep(forTimeInterval: 1)
board.clearContents(); guard board.setString("Rydool newer fixture", forType: .string) else { fail("Cannot seed second item") }
Thread.sleep(forTimeInterval: 1)
guard let rawBar = attribute(app, "AXExtrasMenuBar"), CFGetTypeID(rawBar) == AXUIElementGetTypeID(),
      let status = children(rawBar as! AXUIElement).first else { fail("Missing menu bar") }
let bar = rawBar as! AXUIElement
func historyWindow() -> AXUIElement? {
    (attribute(app, kAXWindowsAttribute as String) as? [AXUIElement] ?? []).first { contains($0, "Rydool — Clipboard") }
}
func activateTarget() {
    _ = target.activate(options: [.activateIgnoringOtherApps])
    for _ in 0..<30 {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID { return }
        Thread.sleep(forTimeInterval: 0.1)
    }
    fail("Test target did not activate")
}
for (index, viaMenu) in [false, true].enumerated() {
    try? FileManager.default.removeItem(atPath: resultFile)
    let expected = String(repeating: sample, count: index + 1)
    activateTarget()
    if viaMenu {
        press(status)
        guard let entry = wait({ find(bar) { contains($0, "Clipboard History") } }) else { fail("History menu entry missing") }
        press(entry)
    } else {
        key(9, flags: [.maskControl, .maskAlternate, .maskShift])
    }
    guard let window = wait({ historyWindow() }), let item = wait({ find(window) { contains($0, sample) } }) else { fail("History window or item missing") }
    if index == 0 {
        guard let pin = find(window, { contains($0, "Pin") }) else { fail("Pin control missing") }
        click(pin)
        Thread.sleep(forTimeInterval: 0.3)
        guard historyWindow() != nil, let unpin = find(window, { (attribute($0, kAXHelpAttribute as String) as? String) == "Unpin" }) else { fail("Pin click closed history or did not pin") }
        click(unpin)
        Thread.sleep(forTimeInterval: 0.3)
        guard historyWindow() != nil else { fail("Unpin click closed history") }
    }
    guard let currentItem = wait({ find(window) { contains($0, sample) } }) else { fail("History item missing after pinning") }
    _ = item
    click(currentItem)
    for _ in 0..<40 {
        if (try? String(contentsOfFile: resultFile, encoding: .utf8)) == expected { break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard (try? String(contentsOfFile: resultFile, encoding: .utf8)) == expected else { fail("Selected item did not reach the focused test editor") }
    guard historyWindow() == nil else { fail("History window did not close") }
}
print("PASS: single click pastes from shortcut and menu; pin controls stay independent")
