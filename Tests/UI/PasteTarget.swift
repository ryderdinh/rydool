import AppKit

final class TestEditor: NSTextView {
    override func paste(_ sender: Any?) {
        let environment = ProcessInfo.processInfo.environment
        guard let name = environment["RYDOOL_TEST_PASTEBOARD"],
              let output = environment["RYDOOL_TEST_PASTE_RESULT"],
              let value = NSPasteboard(name: NSPasteboard.Name(name)).string(forType: .string) else { return }
        insertText(value, replacementRange: selectedRange())
        try? string.write(toFile: output, atomically: true, encoding: .utf8)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let mainMenu = NSMenu()
let editItem = NSMenuItem()
let editMenu = NSMenu(title: "Edit")
editMenu.autoenablesItems = false
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editItem.submenu = editMenu
mainMenu.addItem(editItem)
app.mainMenu = mainMenu
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "Rydool paste test target"
let editor = TestEditor(frame: NSRect(x: 20, y: 20, width: 360, height: 160))
window.contentView?.addSubview(editor)
window.makeKeyAndOrderFront(nil)
window.makeFirstResponder(editor)
app.activate(ignoringOtherApps: true)
app.run()
