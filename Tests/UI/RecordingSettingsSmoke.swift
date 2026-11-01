import AppKit
import ApplicationServices
import Foundation

let app = AXUIElementCreateApplication(pid_t(Int32(CommandLine.arguments[1])!))
func fail(_ message: String) -> Never { fputs("FAIL: \(message)\n", stderr); exit(1) }
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? [] }
func find(_ element: AXUIElement, _ text: String, role: String? = nil) -> AXUIElement? {
    let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { attribute(element, $0 as String) as? String }.joined(separator: " ")
    if label.contains(text) && (role == nil || (attribute(element, kAXRoleAttribute as String) as? String) == role) { return element }
    for child in children(element) { if let item = find(child, text, role: role) { return item } }
    return nil
}
func press(_ element: AXUIElement) { guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { fail("Cannot press control") } }
func windows() -> [AXUIElement] { attribute(app, kAXWindowsAttribute as String) as? [AXUIElement] ?? [] }
func wait(_ search: () -> AXUIElement?) -> AXUIElement? {
    for _ in 0..<30 { if let value = search() { return value }; Thread.sleep(forTimeInterval: 0.2) }
    return nil
}
func setResolution(_ window: AXUIElement, _ value: String) {
    guard let picker = find(window, "Resolution", role: "AXPopUpButton") else { fail("Resolution picker missing") }
    press(picker); Thread.sleep(forTimeInterval: 0.2)
    if find(window, value) == nil { press(picker); Thread.sleep(forTimeInterval: 0.2) }
    guard let option = wait({ find(window, value) }) else { fail("Resolution option missing") }
    press(option); Thread.sleep(forTimeInterval: 0.3)
    guard (attribute(picker, kAXValueAttribute as String) as? String) == value else { fail("Resolution did not change") }
}
func setRate(_ window: AXUIElement, _ value: String) {
    guard let option = find(window, value, role: "AXRadioButton") else { fail("Frame rate option missing") }
    press(option); Thread.sleep(forTimeInterval: 0.2)
    guard (attribute(option, kAXValueAttribute as String) as? NSNumber)?.boolValue == true else { fail("Frame rate did not change") }
}
func setAudio(_ window: AXUIElement, enabled: Bool) {
    guard let toggle = find(window, "System audio", role: "AXCheckBox"),
          let value = attribute(toggle, kAXValueAttribute as String) as? NSNumber else { fail("System audio toggle missing") }
    if value.boolValue != enabled { press(toggle); Thread.sleep(forTimeInterval: 0.2) }
    guard (attribute(toggle, kAXValueAttribute as String) as? NSNumber)?.boolValue == enabled else { fail("System audio setting did not change") }
}
guard AXIsProcessTrusted(), let raw = attribute(app, "AXExtrasMenuBar"), CFGetTypeID(raw) == AXUIElementGetTypeID(),
      let status = children(raw as! AXUIElement).first else { fail("Accessibility menu unavailable") }
let bar = raw as! AXUIElement
func openSettings() -> AXUIElement {
    press(status); Thread.sleep(forTimeInterval: 0.3)
    guard let command = find(bar, "Settings…") else { fail("Settings menu missing") }
    press(command)
    guard let window = wait({ windows().first { (attribute($0, kAXTitleAttribute as String) as? String ?? "").contains("Settings") } }),
          let tab = find(window, "Recording", role: "AXButton") else { fail("Recording settings tab missing") }
    press(tab); Thread.sleep(forTimeInterval: 0.3)
    return window
}
let settings = openSettings()
setResolution(settings, "1080p")
setRate(settings, "30 FPS")
setAudio(settings, enabled: false)
guard let close = attribute(settings, kAXCloseButtonAttribute as String), CFGetTypeID(close) == AXUIElementGetTypeID() else { fail("Settings close button missing") }
press(close as! AXUIElement); Thread.sleep(forTimeInterval: 0.3)
press(status); Thread.sleep(forTimeInterval: 0.3)
guard let record = find(bar, "Record Screen") else { fail("Recording menu missing") }
press(record)
guard let setup = wait({ windows().first { find($0, "Start recording") != nil } }),
      let popupResolution = find(setup, "Resolution", role: "AXPopUpButton"),
      (attribute(popupResolution, kAXValueAttribute as String) as? String) == "1080p",
      let popupRate = find(setup, "30 FPS", role: "AXRadioButton"),
      (attribute(popupRate, kAXValueAttribute as String) as? NSNumber)?.boolValue == true else { fail("Settings did not appear in recording setup") }
setAudio(setup, enabled: false)
setResolution(setup, "720p")
setRate(setup, "60 FPS")
setAudio(setup, enabled: true)
guard let cancel = find(setup, "Cancel", role: "AXButton") else { fail("Setup cancel button missing") }
press(cancel); Thread.sleep(forTimeInterval: 0.3)
let restoredSettings = openSettings()
guard let restoredResolution = find(restoredSettings, "Resolution", role: "AXPopUpButton"),
      (attribute(restoredResolution, kAXValueAttribute as String) as? String) == "720p",
      let restoredRate = find(restoredSettings, "60 FPS", role: "AXRadioButton"),
      (attribute(restoredRate, kAXValueAttribute as String) as? NSNumber)?.boolValue == true,
      let restoredAudio = find(restoredSettings, "System audio", role: "AXCheckBox"),
      (attribute(restoredAudio, kAXValueAttribute as String) as? NSNumber)?.boolValue == true else { fail("Setup changes did not appear in Settings") }
print("PASS: recording settings and setup synchronize in both directions")
