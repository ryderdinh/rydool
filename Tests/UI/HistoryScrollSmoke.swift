import AppKit
import ApplicationServices
import Foundation

let app = AXUIElementCreateApplication(pid_t(Int32(CommandLine.arguments[1])!))
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
func wait(_ body: () -> AXUIElement?) -> AXUIElement? {
    for _ in 0..<40 { if let found = body() { return found }; Thread.sleep(forTimeInterval: 0.1) }
    return nil
}
func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { fail("Cannot create key event") }
    down.flags = flags; up.flags = flags
    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
}
func historyWindow() -> AXUIElement? {
    (attribute(app, kAXWindowsAttribute as String) as? [AXUIElement] ?? []).first {
        (attribute($0, kAXTitleAttribute as String) as? String) == "Rydool — Clipboard"
    }
}
func open() -> AXUIElement {
    key(9, flags: [.maskControl, .maskAlternate, .maskShift])
    guard let window = wait({ historyWindow() }) else { fail("History did not open") }
    Thread.sleep(forTimeInterval: 0.5)
    return window
}
func outline(_ window: AXUIElement) -> AXUIElement {
    guard let result = find(window, { (attribute($0, kAXRoleAttribute as String) as? String) == "AXOutline" }) else { fail("History list missing") }
    return result
}
func scrollBar(_ window: AXUIElement) -> AXUIElement {
    guard let scroll = find(window, { (attribute($0, kAXRoleAttribute as String) as? String) == "AXScrollArea" }),
          let raw = attribute(scroll, kAXVerticalScrollBarAttribute as String), CFGetTypeID(raw) == AXUIElementGetTypeID() else { fail("Vertical scrollbar missing") }
    return raw as! AXUIElement
}
func scrollValue(_ bar: AXUIElement) -> Double { (attribute(bar, kAXValueAttribute as String) as? NSNumber)?.doubleValue ?? -1 }
func assertNoSelection(_ window: AXUIElement) {
    let selected = attribute(outline(window), kAXSelectedRowsAttribute as String) as? [AXUIElement] ?? []
    guard selected.isEmpty else { fail("A history item stayed selected on opening") }
}
guard AXIsProcessTrusted() else { fail("Accessibility permission required") }
let first = open()
assertNoSelection(first)
key(125)
Thread.sleep(forTimeInterval: 0.2)
guard !(attribute(outline(first), kAXSelectedRowsAttribute as String) as? [AXUIElement] ?? []).isEmpty else { fail("Keyboard navigation did not select a row") }
let bar = scrollBar(first)
guard AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, 1.0 as CFNumber) == .success else { fail("Cannot scroll to bottom") }
Thread.sleep(forTimeInterval: 0.4)
guard scrollValue(bar) > 0.9 else { fail("List did not scroll to bottom") }
guard let close = attribute(first, kAXCloseButtonAttribute as String), CFGetTypeID(close) == AXUIElementGetTypeID(),
      AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString) == .success else { fail("Cannot close history") }
Thread.sleep(forTimeInterval: 0.3)
let reopened = open()
assertNoSelection(reopened)
let position = scrollValue(scrollBar(reopened))
guard position >= 0 && position < 0.05 else { fail("History reopened away from the top: \(position)") }
print("PASS: history reopens at the top with no selected row")
