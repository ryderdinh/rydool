import AppKit
import ApplicationServices
import Foundation

let app = AXUIElementCreateApplication(pid_t(Int32(CommandLine.arguments[1])!))
let directory = CommandLine.arguments[2]
func fail(_ text: String) -> Never { fputs("FAIL: \(text)\n", stderr); exit(1) }
func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}
func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? [] }
func find(_ element: AXUIElement, _ predicate: (AXUIElement) -> Bool) -> AXUIElement? {
    if predicate(element) { return element }
    for child in children(element) { if let found = find(child, predicate) { return found } }
    return nil
}
func text(_ element: AXUIElement) -> String {
    [kAXTitleAttribute as String, kAXDescriptionAttribute as String, kAXValueAttribute as String]
        .compactMap { attribute(element, $0) as? String }.joined(separator: " ")
}
func findText(_ element: AXUIElement, _ value: String) -> AXUIElement? { find(element) { text($0).contains(value) } }
func press(_ element: AXUIElement) { guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { fail("Cannot press control") } }
func wait(_ body: () -> AXUIElement?) -> AXUIElement? {
    for _ in 0..<30 { if let value = body() { return value }; Thread.sleep(forTimeInterval: 0.1) }
    return nil
}
func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { fail("Cannot create key event") }
    down.flags = flags; up.flags = flags
    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
}
guard AXIsProcessTrusted() else { fail("Accessibility permission required") }
guard let raw = attribute(app, "AXExtrasMenuBar"), CFGetTypeID(raw) == AXUIElementGetTypeID(),
      let status = children(raw as! AXUIElement).first else { fail("Status item missing") }
let bar = raw as! AXUIElement
press(status); Thread.sleep(forTimeInterval: 0.8)
guard findText(bar, "Add application") == nil else { fail("Detailed settings still appear in the menu") }
guard let settings = findText(bar, "Settings") else { fail("Settings entry missing from menu") }
press(settings)
guard let settingsWindow = wait({ (attribute(app, kAXWindowsAttribute as String) as? [AXUIElement] ?? []).first { text($0).contains("Rydool — Settings") } }) else { fail("Settings window missing") }
func selectSection(_ window: AXUIElement, _ name: String) {
    guard let item = wait({ find(window) { (attribute($0, kAXRoleAttribute as String) as? String) == "AXButton" && text($0).contains(name) } }) else { fail("Settings section missing: \(name)") }
    press(item)
    Thread.sleep(forTimeInterval: 0.3)
}
guard findText(settingsWindow, "Launch Rydool at login") != nil else { fail("General settings missing") }
selectSection(settingsWindow, "Clipboard")
guard findText(settingsWindow, "Unknown application") != nil else { fail("Existing unresolved application is not shown") }
guard let add = findText(settingsWindow, "Add application") else { fail("Add application control missing") }
DispatchQueue.global().async { _ = AXUIElementPerformAction(add, kAXPressAction as CFString) }
guard wait({ findText(app, "Choose applications to exclude") }) != nil else { fail("Application chooser did not open") }
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid_t(Int32(CommandLine.arguments[1])!) else { fail("Chooser is not foreground") }
key(5, flags: [.maskCommand, .maskShift]) // Go to Folder
Thread.sleep(forTimeInterval: 0.5)
guard let field = wait({ find(app) { (attribute($0, kAXRoleAttribute as String) as? String) == "AXTextField" && (attribute($0, kAXFocusedAttribute as String) as? Bool == true) } }) else { fail("Go to Folder field missing") }
guard AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, directory as CFTypeRef) == .success else { fail("Cannot enter fixture directory") }
key(36); Thread.sleep(forTimeInterval: 0.8)
guard let fixture = wait({ findText(app, "Rydool Fixture") }) else { fail("Fixture application missing in chooser") }
var row = fixture
for _ in 0..<4 {
    if (attribute(row, kAXRoleAttribute as String) as? String) == "AXRow" { break }
    guard let parent = attribute(row, kAXParentAttribute as String), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
    row = parent as! AXUIElement
}
guard (attribute(row, kAXRoleAttribute as String) as? String) == "AXRow",
      AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success else { fail("Cannot select fixture application") }
guard let confirm = wait({ find(app) { (attribute($0, kAXRoleAttribute as String) as? String) == "AXButton" && (attribute($0, kAXTitleAttribute as String) as? String) == "Add" } }) else { fail("Application chooser confirm button missing") }
guard (attribute(confirm, kAXEnabledAttribute as String) as? Bool) == true else { fail("Chooser does not allow the selected application") }
press(confirm); Thread.sleep(forTimeInterval: 0.8)
guard findText(app, "Choose applications to exclude") == nil else { fail("Application chooser remained open after confirming") }
guard findText(settingsWindow, "Rydool Fixture") != nil else { fail("Selected application missing from settings") }
guard let remove = findText(settingsWindow, "Remove Rydool Fixture from list") else { fail("Remove control missing") }
press(remove); Thread.sleep(forTimeInterval: 0.3)
guard findText(settingsWindow, "Rydool Fixture") == nil, findText(settingsWindow, "Unknown application") != nil else { fail("Remove changed the wrong application") }
selectSection(settingsWindow, "Shortcuts")
guard let change = findText(settingsWindow, "Change shortcut") else { fail("Shortcut settings missing") }
press(change)
guard wait({ findText(settingsWindow, "Press a shortcut") }) != nil else { fail("Shortcut recording did not start") }
selectSection(settingsWindow, "General")
selectSection(settingsWindow, "Shortcuts")
guard findText(settingsWindow, "Press a shortcut") == nil, let changeAgain = findText(settingsWindow, "Change shortcut") else { fail("Changing sections did not cancel shortcut recording") }
press(changeAgain)
guard wait({ findText(settingsWindow, "Press a shortcut") }) != nil else { fail("Shortcut recording did not restart") }
guard let rawClose = attribute(settingsWindow, kAXCloseButtonAttribute as String), CFGetTypeID(rawClose) == AXUIElementGetTypeID() else { fail("Settings close button missing") }
press(rawClose as! AXUIElement)
press(status)
guard let reopen = wait({ findText(bar, "Settings") }) else { fail("Settings entry missing after closing") }
press(reopen)
guard let reopened = wait({ (attribute(app, kAXWindowsAttribute as String) as? [AXUIElement] ?? []).first { text($0).contains("Rydool — Settings") } }),
      findText(reopened, "Press a shortcut") == nil,
      findText(reopened, "Change shortcut") != nil else { fail("Closing settings did not cancel shortcut recording") }
print("PASS: separate settings window, application exclusions and shortcut recording cleanup")
