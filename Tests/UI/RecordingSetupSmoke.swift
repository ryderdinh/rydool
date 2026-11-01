import AppKit
import ApplicationServices
import Foundation

let app = AXUIElementCreateApplication(pid_t(Int32(CommandLine.arguments[1])!))
func fail(_ message: String) -> Never { fputs("FAIL: \(message)\n", stderr); exit(1) }
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
}
func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? [] }
func find(_ element: AXUIElement, _ text: String) -> AXUIElement? {
    let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { attribute(element, $0 as String) as? String }.joined(separator: " ")
    if label.contains(text) { return element }
    for child in children(element) { if let result = find(child, text) { return result } }
    return nil
}
func press(_ element: AXUIElement) { guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { fail("Cannot press control") } }
func windows() -> [AXUIElement] { attribute(app, kAXWindowsAttribute as String) as? [AXUIElement] ?? [] }
guard AXIsProcessTrusted(), let raw = attribute(app, "AXExtrasMenuBar"), CFGetTypeID(raw) == AXUIElementGetTypeID(),
      let status = children(raw as! AXUIElement).first else { fail("Accessibility menu unavailable") }
press(status); Thread.sleep(forTimeInterval: 0.4)
guard let record = find(raw as! AXUIElement, "Record Screen") else { fail("Recording menu action missing") }
press(record); Thread.sleep(forTimeInterval: 0.6)
guard let window = windows().first(where: { find($0, "Start recording") != nil }) else { fail("Recording setup did not open") }
for name in ["Display", "Full screen", "Selected area", "System audio", "Microphone", "Cancel"] {
    guard find(window, name) != nil else { fail("Missing \(name)") }
}
guard let area = find(window, "Selected area") else { fail("Area option missing") }
press(area); Thread.sleep(forTimeInterval: 0.2)
guard let select = find(window, "Select area") else { fail("Area selection button missing") }
press(select); Thread.sleep(forTimeInterval: 0.5)
guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
      let up = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false) else { fail("Escape unavailable") }
down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.5)
press(status); Thread.sleep(forTimeInterval: 0.3)
guard find(raw as! AXUIElement, "Record Screen") != nil, find(raw as! AXUIElement, "Stop recording") == nil else { fail("Canceling selection did not return to idle") }
print("PASS: recording setup, audio choices and canceling area selection")
