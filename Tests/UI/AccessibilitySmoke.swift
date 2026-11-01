import AppKit
import ApplicationServices
import Foundation

let app = AXUIElementCreateApplication(pid_t(Int32(CommandLine.arguments[1])!))
let board = NSPasteboard(name: NSPasteboard.Name(CommandLine.arguments[2]))
func fail(_ message: String) -> Never { fputs("FAIL: \(message)\n", stderr); exit(1) }
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
}
func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
}
func find(_ element: AXUIElement, where matches: (AXUIElement) -> Bool) -> AXUIElement? {
    if matches(element) { return element }
    for child in children(element) { if let found = find(child, where: matches) { return found } }
    return nil
}
func findText(_ element: AXUIElement, _ text: String) -> AXUIElement? {
    find(element) { node in
        let description = attribute(node, kAXDescriptionAttribute as String) as? String ?? ""
        let value = attribute(node, kAXValueAttribute as String) as? String ?? ""
        return description.contains(text) || value.contains(text)
    }
}
func press(_ element: AXUIElement) {
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { fail("Accessibility press failed") }
}
func windows() -> [AXUIElement] { attribute(app, kAXWindowsAttribute as String) as? [AXUIElement] ?? [] }
guard AXIsProcessTrusted() else { fail("This process needs macOS Accessibility permission for UI testing") }
guard let rawBar = attribute(app, "AXExtrasMenuBar"), CFGetTypeID(rawBar) == AXUIElementGetTypeID() else { fail("Missing menu bar") }
let bar = rawBar as! AXUIElement
guard let status = children(bar).first else { fail("Missing status item") }
press(status); Thread.sleep(forTimeInterval: 1)
func waitForText(_ root: AXUIElement, _ text: String) -> AXUIElement? {
    for _ in 0..<15 {
        if let found = findText(root, text) { return found }
        Thread.sleep(forTimeInterval: 0.2)
    }
    return nil
}
guard waitForText(bar, "Pause Clipboard History") != nil else { fail("Clipboard history is not enabled by default") }
let synthetic = "RYDOOL synthetic clipboard 741"
board.clearContents()
guard board.setString(synthetic, forType: .string) else { fail("Cannot write isolated pasteboard") }
Thread.sleep(forTimeInterval: 1.2)
guard findText(bar, "Clipboard History") != nil else { fail("Missing history action") }
press(status); Thread.sleep(forTimeInterval: 0.3)
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid_t(Int32(CommandLine.arguments[1])!) else { fail("Test app is not foreground") }
guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
      let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { fail("Cannot create shortcut event") }
down.flags = [.maskControl, .maskAlternate, .maskShift]; up.flags = [.maskControl, .maskAlternate, .maskShift]
down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.8)
guard let window = windows().first else { fail("History window not shown") }
guard findText(window, synthetic) != nil else { fail("Copied item missing from history") }
guard let pin = findText(window, "Pin") else { fail("Pin button missing") }
press(pin); Thread.sleep(forTimeInterval: 0.3)
guard let search = find(window, where: { attribute($0, kAXRoleAttribute as String) as? String == kAXTextFieldRole as String }) else { fail("Search field missing") }
guard AXUIElementSetAttributeValue(search, kAXValueAttribute as CFString, "no-match-741" as CFTypeRef) == .success else { fail("Cannot set search") }
Thread.sleep(forTimeInterval: 0.4)
guard findText(window, "No results found") != nil else { fail("Search did not filter") }
guard AXUIElementSetAttributeValue(search, kAXValueAttribute as CFString, "synthetic" as CFTypeRef) == .success else { fail("Cannot set search") }
Thread.sleep(forTimeInterval: 0.4)
guard findText(window, synthetic) != nil else { fail("Search did not return item") }
let second = "RYDOOL synthetic clipboard 742"
board.clearContents(); board.setString(second, forType: .string)
Thread.sleep(forTimeInterval: 1)
guard findText(window, second) != nil else { fail("Second item missing") }
_ = AXUIElementSetAttributeValue(search, kAXFocusedAttribute as CFString, kCFBooleanTrue)
Thread.sleep(forTimeInterval: 0.2)
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid_t(Int32(CommandLine.arguments[1])!) else { fail("History window is not foreground") }
board.clearContents()
func key(_ code: CGKeyCode) {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { fail("Cannot create key event") }
    down.flags = []; up.flags = []
    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.08)
}
key(125); key(125); key(36) // Down to the second item, Return
Thread.sleep(forTimeInterval: 0.4)
guard board.string(forType: .string) == second else { fail("Keyboard selection did not restore second item") }
press(status); Thread.sleep(forTimeInterval: 0.5)
if findText(bar, "Allow Screen Recording") != nil {
    guard let capture = findText(bar, "Capture Area") else { fail("Capture action missing") }
    press(capture); Thread.sleep(forTimeInterval: 0.8)
    guard let permissionWindow = windows().first(where: { findText($0, "needs Screen Recording permission") != nil }) else { fail("Permission explanation not shown") }
    guard let notNow = findText(permissionWindow, "Not Now") else { fail("Permission window cannot be dismissed") }
    press(notNow)
    print("PASS: denied-permission explanation and cancellation")
} else {
    print("SKIP: permission explanation; screen access already granted")
}
board.releaseGlobally()
print("PASS: enabled by default, global shortcut, isolated clipboard, pin, search and keyboard copy")
