import AppKit
import ApplicationServices
import Foundation

let vietnamese = CommandLine.arguments.contains("--vi")
func tr(_ english: String) -> String {
    guard vietnamese else { return english }
    return ["Record Screen": "Quay màn hình", "Start recording": "Bắt đầu quay",
            "Display": "Màn hình", "Full screen": "Toàn màn hình", "Selected area": "Vùng được chọn",
            "Resolution": "Độ phân giải", "Frame rate": "Tốc độ khung hình", "Quality": "Chất lượng",
            "System audio": "Âm thanh hệ thống", "Microphone": "Micro", "Cancel": "Hủy",
            "Select area": "Chọn vùng", "Stop recording": "Dừng quay"][english] ?? english
}
let app = AXUIElementCreateApplication(pid_t(Int32(CommandLine.arguments[1])!))
func fail(_ message: String) -> Never { fputs("FAIL: \(message)\n", stderr); exit(1) }
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
}
func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? [] }
func find(_ element: AXUIElement, _ text: String, role: String? = nil) -> AXUIElement? {
    let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { attribute(element, $0 as String) as? String }.joined(separator: " ")
    if label.contains(tr(text)) && (role == nil || (attribute(element, kAXRoleAttribute as String) as? String) == role) { return element }
    for child in children(element) { if let result = find(child, text, role: role) { return result } }
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
for name in ["Display", "Full screen", "Selected area", "Resolution", "Frame rate", "Quality", "System audio", "Microphone", "Cancel"] {
    guard find(window, name) != nil else { fail("Missing \(name)") }
}
guard let audio = find(window, "System audio", role: "AXCheckBox"),
      let audioValue = attribute(audio, kAXValueAttribute as String) as? NSNumber,
      audioValue.boolValue else { fail("System audio should be enabled by default") }
press(audio)
guard let changed = attribute(audio, kAXValueAttribute as String) as? NSNumber,
      !changed.boolValue else { fail("System audio cannot be disabled") }
guard let microphone = find(window, "Microphone", role: "AXCheckBox"),
      let microphoneValue = attribute(microphone, kAXValueAttribute as String) as? NSNumber,
      !microphoneValue.boolValue else { fail("Microphone should be disabled by default") }
guard let resolution = find(window, "Resolution", role: "AXPopUpButton") else { fail("Resolution picker missing") }
press(resolution); Thread.sleep(forTimeInterval: 0.2)
guard let option = find(window, "1080p") else { fail("1080p option missing") }
press(option); Thread.sleep(forTimeInterval: 0.3)
guard (attribute(resolution, kAXValueAttribute as String) as? String) == "1080p" else { fail("Resolution selection did not update") }
guard let rate = find(window, "30 FPS", role: "AXRadioButton") else { fail("Frame rate option missing") }
press(rate); Thread.sleep(forTimeInterval: 0.2)
guard (attribute(rate, kAXValueAttribute as String) as? NSNumber)?.boolValue == true else { fail("Frame rate selection did not update") }
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
