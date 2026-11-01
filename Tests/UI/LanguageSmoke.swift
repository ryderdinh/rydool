import AppKit
import ApplicationServices
import Foundation

let app = AXUIElementCreateApplication(pid_t(Int32(CommandLine.arguments[1])!))
let restoring = CommandLine.arguments.contains("restore")
func fail(_ message: String) -> Never { fputs("FAIL: \(message)\n", stderr); exit(1) }
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
func findText(_ element: AXUIElement, _ textValue: String) -> AXUIElement? { find(element) { text($0).contains(textValue) } }
func wait(_ body: () -> AXUIElement?) -> AXUIElement? {
    for _ in 0..<40 { if let found = body() { return found }; Thread.sleep(forTimeInterval: 0.1) }
    return nil
}
func press(_ element: AXUIElement) { guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { fail("Cannot press control") } }
func windows() -> [AXUIElement] { attribute(app, kAXWindowsAttribute as String) as? [AXUIElement] ?? [] }
guard AXIsProcessTrusted(), let raw = attribute(app, "AXExtrasMenuBar"), CFGetTypeID(raw) == AXUIElementGetTypeID(),
      let status = children(raw as! AXUIElement).first else { fail("Status item or accessibility unavailable") }
let bar = raw as! AXUIElement
func openMenu(expected: String) {
    for _ in 0..<4 {
        if findText(bar, expected) != nil { return }
        press(status)
        Thread.sleep(forTimeInterval: 0.4)
    }
    fail("Menu did not open in the expected language")
}
func settingsWindow(_ title: String) -> AXUIElement? { windows().first { text($0).contains(title) } }

let initialCapture = restoring ? "区域截图" : "Capture Area"
let initialSettings = restoring ? "设置…" : "Settings…"
openMenu(expected: initialCapture)
guard findText(bar, initialCapture) != nil, let entry = findText(bar, initialSettings) else { fail("Initial menu language is incorrect") }
press(entry)
guard let window = wait({ settingsWindow(restoring ? "Rydool — 设置" : "Rydool — Settings") }) else { fail("Initial settings language is incorrect") }
if restoring {
    guard findText(window, "登录时启动 Rydool") != nil else { fail("Saved language not applied to settings") }
    print("PASS: Chinese remains selected after relaunch")
    exit(0)
}
guard findText(window, "Launch Rydool at login") != nil else { fail("English is not the default") }
guard let vietnamese = findText(window, "Tiếng Việt") else { fail("Vietnamese choice missing") }
press(vietnamese)
guard let viWindow = wait({ settingsWindow("Rydool — Cài đặt") }),
      wait({ findText(viWindow, "Mở Rydool khi đăng nhập") }) != nil else { fail("Vietnamese did not apply to the open settings window") }
openMenu(expected: "Chụp vùng")
guard findText(bar, "Chụp vùng") != nil, let history = findText(bar, "Lịch sử clipboard") else { fail("Vietnamese did not apply to the menu") }
press(history)
guard let historyWindow = wait({ settingsWindow("Rydool — Clipboard") }),
      findText(historyWindow, "Chưa có lịch sử clipboard") != nil else { fail("Vietnamese did not apply to clipboard history") }
openMenu(expected: "Chụp vùng")
guard let capture = findText(bar, "Chụp toàn màn hình") else { fail("Vietnamese capture action missing") }
press(capture)
guard let preview = wait({ windows().first { findText($0, "Chỉnh sửa ảnh") != nil } }),
      let edit = findText(preview, "Chỉnh sửa ảnh") else { fail("Vietnamese preview missing") }
press(edit)
guard let editor = wait({ settingsWindow("Rydool — Ảnh chụp màn hình") }),
      wait({ findText(editor, "Vùng chỉnh sửa ảnh") }) != nil else { fail("Vietnamese editor did not open") }
guard let chinese = findText(viWindow, "简体中文") else { fail("Chinese choice missing") }
press(chinese)
guard let zhWindow = wait({ settingsWindow("Rydool — 设置") }),
      wait({ findText(zhWindow, "登录时启动 Rydool") }) != nil else { fail("Chinese did not apply to the open settings window") }
guard let zhHistory = wait({ settingsWindow("Rydool — 剪贴板") }),
      wait({ findText(zhHistory, "剪贴板图像") }) != nil else { fail("Chinese did not apply to the open history window") }
guard let zhEditor = wait({ settingsWindow("Rydool — 截图") }),
      wait({ findText(zhEditor, "截图编辑画布") }) != nil else { fail("Chinese did not apply to the open screenshot editor") }
openMenu(expected: "区域截图")
guard findText(bar, "区域截图") != nil, findText(bar, "剪贴板历史") != nil else { fail("Chinese did not apply to the menu") }
print("PASS: English default and live switching to Vietnamese and Chinese")
