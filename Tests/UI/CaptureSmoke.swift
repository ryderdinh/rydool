import AppKit
import ApplicationServices
import Foundation

let app = AXUIElementCreateApplication(pid_t(Int32(CommandLine.arguments[1])!))
let board = NSPasteboard(name: NSPasteboard.Name(CommandLine.arguments[2]))
let regionMode = CommandLine.arguments.contains("region")
let saveMode = CommandLine.arguments.contains("save")
let shortcutMode = CommandLine.arguments.contains("shortcut")
let historyDisabled = CommandLine.arguments.contains("history-disabled")
let cancelRegion = CommandLine.arguments.contains("cancel-region")
let previewStackMode = CommandLine.arguments.contains("preview-stack")
let previewTimerMode = CommandLine.arguments.contains("preview-timer")
let previewSaveWaitMode = CommandLine.arguments.contains("preview-save-wait")
let editorRecaptureRegion = CommandLine.arguments.contains("editor-recapture-region")
let editorRecaptureMode = CommandLine.arguments.contains("editor-recapture") || editorRecaptureRegion
let previewCopyMode = CommandLine.arguments.contains("preview-copy") || previewStackMode || previewTimerMode || previewSaveWaitMode
func fail(_ message: String) -> Never { fputs("FAIL: \(message)\n", stderr); exit(1) }
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
}
func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? [] }
func findText(_ element: AXUIElement, _ text: String) -> AXUIElement? {
    let description = attribute(element, kAXDescriptionAttribute as String) as? String ?? ""
    let value = attribute(element, kAXValueAttribute as String) as? String ?? ""
    let title = attribute(element, kAXTitleAttribute as String) as? String ?? ""
    if description.contains(text) || value.contains(text) || title.contains(text) { return element }
    for child in children(element) { if let result = findText(child, text) { return result } }
    return nil
}
func findRole(_ element: AXUIElement, _ role: String) -> AXUIElement? {
    if (attribute(element, kAXRoleAttribute as String) as? String) == role { return element }
    for child in children(element) { if let result = findRole(child, role) { return result } }
    return nil
}
func press(_ element: AXUIElement) {
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { fail("Cannot press UI control") }
}
func windows() -> [AXUIElement] { attribute(app, kAXWindowsAttribute as String) as? [AXUIElement] ?? [] }
func frame(_ element: AXUIElement) -> CGRect? {
    guard let p = attribute(element, kAXPositionAttribute as String), CFGetTypeID(p) == AXValueGetTypeID(),
          let s = attribute(element, kAXSizeAttribute as String), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}
guard AXIsProcessTrusted() else { fail("Accessibility permission required") }
guard let raw = attribute(app, "AXExtrasMenuBar"), CFGetTypeID(raw) == AXUIElementGetTypeID() else { fail("No menu bar") }
let bar = raw as! AXUIElement
guard let status = children(bar).first else { fail("No status item") }
press(status); Thread.sleep(forTimeInterval: 1)
func waitForText(_ root: AXUIElement, _ text: String) -> AXUIElement? {
    for _ in 0..<15 {
        if let found = findText(root, text) { return found }
        Thread.sleep(forTimeInterval: 0.2)
    }
    return nil
}
guard let pause = waitForText(bar, "Pause Clipboard History") else { fail("Clipboard history is not enabled by default") }
if historyDisabled { press(pause) }
let action = regionMode ? "Capture Area" : "Capture Full Screen"
guard let capture = findText(bar, action) else { fail("No capture action") }
if shortcutMode {
    press(status); Thread.sleep(forTimeInterval: 0.2)
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid_t(Int32(CommandLine.arguments[1])!) else { fail("Test app is not foreground") }
    let code: CGKeyCode = regionMode ? 21 : 20 // ANSI 4 / ANSI 3
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { fail("Cannot create shortcut event") }
    down.flags = [.maskControl, .maskAlternate, .maskShift]; up.flags = [.maskControl, .maskAlternate, .maskShift]
    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
} else { press(capture) }
Thread.sleep(forTimeInterval: 1)
let display = CGDisplayBounds(CGMainDisplayID())
let oldMouse = CGEvent(source: nil)?.location
func mouse(_ type: CGEventType, _ point: CGPoint) {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { fail("Cannot create mouse event") }
    event.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.12)
}
func hoverPreview(_ preview: AXUIElement) {
    guard let rect = frame(preview) else { fail("Preview frame missing") }
    mouse(.mouseMoved, CGPoint(x: rect.midX, y: rect.midY))
    guard waitForText(preview, "Close preview") != nil else { fail("Preview controls did not appear on hover") }
}
func click(_ element: AXUIElement) {
    guard let rect = frame(element) else { fail("Control frame missing") }
    let point = CGPoint(x: rect.midX, y: rect.midY)
    mouse(.mouseMoved, point); mouse(.leftMouseDown, point); mouse(.leftMouseUp, point)
}
if cancelRegion {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false) else { fail("Cannot create Escape event") }
    down.flags = []; up.flags = []
    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.5)
    guard board.data(forType: .png) == nil,
          !windows().contains(where: { findText($0, "Edit screenshot") != nil }) else { fail("Canceling capture modified the clipboard") }
    board.releaseGlobally()
    print("PASS: canceling selection leaves the clipboard unchanged")
    exit(0)
}
if regionMode {
    let start = CGPoint(x: display.minX + display.width * 0.2, y: display.minY + display.height * 0.2)
    let end = CGPoint(x: display.minX + display.width * 0.8, y: display.minY + display.height * 0.8)
    mouse(.leftMouseDown, start); mouse(.leftMouseDragged, end); mouse(.leftMouseUp, end)
    Thread.sleep(forTimeInterval: 0.4)
}
guard var preview = windows().first(where: { findText($0, "Edit screenshot") != nil }),
      findText(preview, "Edit screenshot") != nil else { fail("Screenshot preview is missing") }
mouse(.mouseMoved, CGPoint(x: display.midX, y: display.midY))
guard findText(preview, "Copy") == nil, findText(preview, "Save") == nil,
      findText(preview, "Close preview") == nil else { fail("Preview controls should be hidden until hover") }
hoverPreview(preview)
guard
      findText(preview, "Copy") != nil,
      findText(preview, "Save") != nil,
      findText(preview, "Close preview") != nil else { fail("Screenshot preview or its actions are missing") }
guard let initialPreviewFrame = frame(preview), initialPreviewFrame.width < 200, initialPreviewFrame.height < 160 else { fail("Screenshot preview is too large") }
guard !windows().contains(where: { findText($0, "Arrow") != nil }) else { fail("Editor appeared before selecting preview") }
guard let originalPNG = board.data(forType: .png), let originalBitmap = NSBitmapImageRep(data: originalPNG) else { fail("Capture did not automatically copy PNG") }
if regionMode {
    guard (214...218).contains(originalBitmap.pixelsWide), (142...146).contains(originalBitmap.pixelsHigh) else { fail("Automatically copied region has wrong dimensions") }
} else {
    guard originalBitmap.pixelsWide == 360, originalBitmap.pixelsHigh == 240 else { fail("Automatically copied full screen has wrong dimensions") }
}
let capturedChangeCount = board.changeCount
if previewSaveWaitMode {
    guard let save = findText(preview, "Save") else { fail("Preview save action missing") }
    DispatchQueue.global().async { _ = AXUIElementPerformAction(save, kAXPressAction as CFString) }
    Thread.sleep(forTimeInterval: 1)
    guard let cancel = windows().compactMap({ findText($0, "Cancel") }).first else { fail("Preview save dialog missing") }
    Thread.sleep(forTimeInterval: 6)
    press(cancel); Thread.sleep(forTimeInterval: 0.4)
    guard let restored = windows().first(where: { findText($0, "Edit screenshot") != nil }) else { fail("Preview hid while save dialog was open") }
    preview = restored
}
if previewTimerMode {
    guard let previewFrame = frame(preview) else { fail("Preview frame missing") }
    mouse(.mouseMoved, CGPoint(x: previewFrame.midX, y: previewFrame.midY))
    Thread.sleep(forTimeInterval: 6)
    guard windows().contains(where: { findText($0, "Edit screenshot") != nil }) else { fail("Preview hid while pointer was over it") }
    mouse(.mouseMoved, CGPoint(x: display.midX, y: display.midY))
    Thread.sleep(forTimeInterval: 6)
    guard !windows().contains(where: { findText($0, "Edit screenshot") != nil }) else { fail("Preview did not auto-hide") }
    guard board.changeCount == capturedChangeCount, board.data(forType: .png) == originalPNG else { fail("Auto-hide changed the clipboard") }
    press(status); Thread.sleep(forTimeInterval: 0.5)
    guard let recent = waitForText(bar, "Recent Screenshots") else { fail("Hidden screenshot cannot be restored") }
    press(recent); Thread.sleep(forTimeInterval: 0.5)
    guard let restored = windows().first(where: { findText($0, "Edit screenshot") != nil }) else { fail("Recent screenshot did not reopen") }
    preview = restored
    if let oldMouse { mouse(.mouseMoved, oldMouse) }
}
if previewStackMode {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 20, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 20, keyDown: false) else { fail("Cannot create shortcut event") }
    down.flags = [.maskControl, .maskAlternate, .maskShift]; up.flags = down.flags
    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 1)
    let previews = windows().filter { findText($0, "Edit screenshot") != nil }
    guard previews.count == 2 else { fail("Multiple captures did not retain two previews") }
    hoverPreview(previews[0])
    guard let close = findText(previews[0], "Close preview") else { fail("Preview close action missing") }
    press(close); Thread.sleep(forTimeInterval: 0.3)
    guard let remaining = windows().first(where: { findText($0, "Edit screenshot") != nil }) else { fail("Closing one preview removed the other") }
    preview = remaining
}
if previewCopyMode {
    hoverPreview(preview)
    guard let previewCopy = findText(preview, "Copy") else { fail("Preview copy action missing") }
    click(previewCopy); Thread.sleep(forTimeInterval: 0.6)
    guard !windows().contains(where: { findText($0, "Arrow") != nil }) else { fail("Copy also opened the editor") }
    guard let png = board.data(forType: .png), let bitmap = NSBitmapImageRep(data: png) else { fail("Preview did not copy the screenshot") }
    if regionMode {
        guard (214...218).contains(bitmap.pixelsWide), (142...146).contains(bitmap.pixelsHigh) else { fail("Preview copied the wrong region") }
    } else {
        guard bitmap.pixelsWide == 360, bitmap.pixelsHigh == 240 else { fail("Preview copied the wrong full screen") }
    }
    guard let close = findText(preview, "Close preview") else { fail("Preview close action missing") }
    click(close); Thread.sleep(forTimeInterval: 0.3)
    guard !windows().contains(where: { findText($0, "Edit screenshot") != nil }) else { fail("Preview did not close") }
    board.releaseGlobally()
    print("PASS: preview appears after capture, copies PNG, and closes")
    exit(0)
}
guard let edit = findText(preview, "Edit screenshot") else { fail("Preview edit action missing") }
_ = edit
guard let previewFrame = frame(preview) else { fail("Preview frame missing") }
let blankPoint = CGPoint(x: previewFrame.midX, y: previewFrame.midY)
mouse(.mouseMoved, blankPoint); mouse(.leftMouseDown, blankPoint); mouse(.leftMouseUp, blankPoint)
Thread.sleep(forTimeInterval: 0.5)
guard windows().contains(where: { findText($0, "Arrow") != nil }) else { fail("Editor did not open from preview") }
for _ in 0..<10 where NSWorkspace.shared.frontmostApplication?.processIdentifier != pid_t(Int32(CommandLine.arguments[1])!) { Thread.sleep(forTimeInterval: 0.1) }
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid_t(Int32(CommandLine.arguments[1])!) else { fail("Editor did not become foreground") }
guard let escapeDown = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
      let escapeUp = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false) else { fail("Cannot create Escape event") }
escapeDown.flags = []; escapeUp.flags = []
escapeDown.post(tap: .cghidEventTap); escapeUp.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.4)
guard let restoredPreview = windows().first(where: { findText($0, "Edit screenshot") != nil }),
      let editAgain = findText(restoredPreview, "Edit screenshot") else { fail("Canceling the editor lost the preview") }
press(editAgain); Thread.sleep(forTimeInterval: 0.5)
guard let firstEditor = windows().first(where: { findText($0, "Arrow") != nil }),
      let rawClose = attribute(firstEditor, kAXCloseButtonAttribute as String), CFGetTypeID(rawClose) == AXUIElementGetTypeID() else { fail("Editor window close button missing") }
press(rawClose as! AXUIElement); Thread.sleep(forTimeInterval: 0.4)
guard let previewAfterClose = windows().first(where: { findText($0, "Edit screenshot") != nil }),
      let reopen = findText(previewAfterClose, "Edit screenshot") else { fail("Closing the editor lost the preview") }
press(reopen); Thread.sleep(forTimeInterval: 0.5)
guard let overlay = windows().first(where: { findText($0, "Arrow") != nil }), let arrow = findText(overlay, "Arrow"), let undo = findText(overlay, "Undo") else { fail("Capture toolbar missing") }
guard (attribute(overlay, kAXTitleAttribute as String) as? String ?? "").contains("Rydool — Screenshot"),
      let windowFrame = frame(overlay), windowFrame.width < display.width, windowFrame.height < display.height,
      let imageCanvas = findText(overlay, "Screenshot canvas"), let canvasFrame = frame(imageCanvas) else { fail("Editor is not a separate image window") }
guard let zoomIn = findText(overlay, "Zoom in"), let zoomOut = findText(overlay, "Zoom out"),
      let fit = findText(overlay, "Fit image to window") ?? findText(overlay, "Fit") else { fail("Zoom controls missing") }
press(zoomIn); Thread.sleep(forTimeInterval: 0.3)
guard let zoomedFrame = frame(imageCanvas), zoomedFrame.width > canvasFrame.width * 1.1 else { fail("Zoom in did not enlarge the canvas") }
press(zoomOut); Thread.sleep(forTimeInterval: 0.3)
guard let reducedFrame = frame(imageCanvas), abs(reducedFrame.width - canvasFrame.width) < 2 else { fail("Zoom out did not restore the scale") }
press(fit); Thread.sleep(forTimeInterval: 0.3)
guard let fittedFrame = frame(imageCanvas), abs(fittedFrame.width - canvasFrame.width) < 2 else { fail("Fit did not restore the initial scale (initial: \(canvasFrame), current: \(String(describing: frame(imageCanvas))))") }
guard let actualSize = findText(overlay, "Actual size") else { fail("Actual size control missing") }
press(actualSize); Thread.sleep(forTimeInterval: 0.3)
let expectedWidth = display.width * (regionMode ? 0.6 : 1)
guard let actualFrame = frame(imageCanvas), abs(actualFrame.width - expectedWidth) < 10 else { fail("Actual size did not restore 100%") }
press(fit); Thread.sleep(forTimeInterval: 0.3)
var smallerSize = CGSize(width: windowFrame.width - 100, height: windowFrame.height - 100)
guard let smallerValue = AXValueCreate(.cgSize, &smallerSize),
      AXUIElementSetAttributeValue(overlay, kAXSizeAttribute as CFString, smallerValue) == .success else { fail("Cannot resize editor") }
Thread.sleep(forTimeInterval: 0.3)
guard let resizedFrame = frame(imageCanvas), resizedFrame.width < fittedFrame.width - 5 else { fail("Fit did not update after resizing the editor") }
var minimumSize = CGSize(width: 560, height: 340)
guard let minimumValue = AXValueCreate(.cgSize, &minimumSize),
      AXUIElementSetAttributeValue(overlay, kAXSizeAttribute as CFString, minimumValue) == .success else { fail("Cannot minimize editor") }
Thread.sleep(forTimeInterval: 0.3)
guard let compactWindow = frame(overlay) else { fail("Compact editor frame missing") }
for name in ["Pen", "Arrow", "Rectangle", "Text", "Undo", "Zoom out", "Zoom in", "Fit", "Save As", "Copy"] {
    guard let control = findText(overlay, name), let controlFrame = frame(control),
          compactWindow.contains(controlFrame) else { fail("\(name) is missing or outside the compact editor") }
}
var originalSize = windowFrame.size
guard let originalValue = AXValueCreate(.cgSize, &originalSize),
      AXUIElementSetAttributeValue(overlay, kAXSizeAttribute as CFString, originalValue) == .success else { fail("Cannot restore editor size") }
Thread.sleep(forTimeInterval: 0.3)
guard let restoredFrame = frame(imageCanvas), abs(restoredFrame.width - canvasFrame.width) < 2 else { fail("Fit did not restore after resizing") }
print("PASS: zoom, actual size, fit and window resize update the editor canvas")
let from = CGPoint(x: canvasFrame.minX + canvasFrame.width * 0.2, y: canvasFrame.minY + canvasFrame.height * 0.3)
let to = CGPoint(x: canvasFrame.minX + canvasFrame.width * 0.7, y: canvasFrame.minY + canvasFrame.height * 0.5)
press(arrow)
mouse(.leftMouseDown, from)
mouse(.leftMouseDragged, to)
mouse(.leftMouseUp, to)
if let oldMouse { mouse(.mouseMoved, oldMouse) }
Thread.sleep(forTimeInterval: 0.4)
let undoEnabled = attribute(undo, kAXEnabledAttribute as String) as? Bool ?? false
guard undoEnabled else { fail("Arrow drawing did not enable Undo") }
if editorRecaptureMode {
    let beforeCapture = board.changeCount
    let captureKey: CGKeyCode = editorRecaptureRegion ? 21 : 20
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: captureKey, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: captureKey, keyDown: false) else { fail("Cannot create capture shortcut") }
    down.flags = [.maskControl, .maskAlternate, .maskShift]; up.flags = down.flags
    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 1)
    if editorRecaptureRegion {
        let start = CGPoint(x: display.minX + display.width * 0.2, y: display.minY + display.height * 0.2)
        let end = CGPoint(x: display.minX + display.width * 0.8, y: display.minY + display.height * 0.8)
        mouse(.leftMouseDown, start); mouse(.leftMouseDragged, end); mouse(.leftMouseUp, end)
        Thread.sleep(forTimeInterval: 0.4)
    }
    guard board.changeCount > beforeCapture,
          let newPreview = windows().first(where: { findText($0, "Edit screenshot") != nil }),
          let editSecond = findText(newPreview, "Edit screenshot") else { fail("Capture shortcut did not work while editor was open") }
    guard windows().contains(where: { (attribute($0, kAXTitleAttribute as String) as? String) == "Rydool — Screenshot" }),
          (attribute(undo, kAXEnabledAttribute as String) as? Bool ?? false) else { fail("Taking another screenshot lost the editor or its annotations") }
    press(editSecond); Thread.sleep(forTimeInterval: 0.4)
    let editorWindows = windows().filter { (attribute($0, kAXTitleAttribute as String) as? String) == "Rydool — Screenshot" }
    guard editorWindows.count == 2, let secondEditor = editorWindows.first(where: { !CFEqual($0, overlay) }),
          let close = attribute(secondEditor, kAXCloseButtonAttribute as String), CFGetTypeID(close) == AXUIElementGetTypeID() else { fail("Second editor did not open independently") }
    press(close as! AXUIElement); Thread.sleep(forTimeInterval: 0.3)
    guard let preview = windows().first(where: { findText($0, "Edit screenshot") != nil }) else { fail("Closing second editor did not restore its preview") }
    hoverPreview(preview)
    guard let closePreview = findText(preview, "Close preview") else { fail("Preview close control missing") }
    press(closePreview); Thread.sleep(forTimeInterval: 0.3)
    guard (attribute(undo, kAXEnabledAttribute as String) as? Bool ?? false) else { fail("Closing the second editor changed the first editor") }
}
press(undo); Thread.sleep(forTimeInterval: 0.3)
guard (attribute(undo, kAXEnabledAttribute as String) as? Bool ?? true) == false else { fail("Undo did not remove annotation") }
mouse(.leftMouseDown, from); mouse(.leftMouseDragged, to); mouse(.leftMouseUp, to)
if let oldMouse { mouse(.mouseMoved, oldMouse) }
Thread.sleep(forTimeInterval: 0.3)
guard (attribute(undo, kAXEnabledAttribute as String) as? Bool ?? false) else { fail("Cannot draw after undo") }
guard let textTool = findText(overlay, "Text") else { fail("Text tool missing") }
press(textTool)
let textPoint = CGPoint(x: canvasFrame.minX + canvasFrame.width * 0.35, y: canvasFrame.minY + canvasFrame.height * 0.65)
mouse(.leftMouseDown, textPoint); mouse(.leftMouseUp, textPoint)
if let oldMouse { mouse(.mouseMoved, oldMouse) }
Thread.sleep(forTimeInterval: 0.3)
guard let field = findRole(overlay, "AXTextField") else { fail("Text editor missing") }
let sampleText = "Tiếng Việt\nDòng hai"
guard AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, sampleText as CFTypeRef) == .success,
      (attribute(field, kAXValueAttribute as String) as? String) == sampleText else { fail("Cannot enter Unicode text") }
guard let save = findText(overlay, "Save As") else { fail("Save action missing") }
// AXPress may wait for the nested save dialog, so dismiss it from this thread.
DispatchQueue.global().async { _ = AXUIElementPerformAction(save, kAXPressAction as CFString) }
Thread.sleep(forTimeInterval: 1)
guard let cancel = windows().compactMap({ findText($0, "Cancel") }).first else { fail("Save dialog did not appear") }
press(cancel); Thread.sleep(forTimeInterval: 0.5)
guard let returnedOverlay = windows().first(where: { findText($0, "Copy") != nil }) else { fail("Editor did not return after cancel") }
if saveMode {
    guard let saveAgain = findText(returnedOverlay, "Save As") else { fail("Save action missing after cancellation") }
    DispatchQueue.global().async { _ = AXUIElementPerformAction(saveAgain, kAXPressAction as CFString) }
    Thread.sleep(forTimeInterval: 0.8)
    func findSaveButton(_ element: AXUIElement) -> AXUIElement? {
        let role = attribute(element, kAXRoleAttribute as String) as? String ?? ""
        let title = attribute(element, kAXTitleAttribute as String) as? String ?? ""
        if role == "AXButton" && title == "Save" { return element }
        for child in children(element) { if let result = findSaveButton(child) { return result } }
        return nil
    }
    guard let saveButton = windows().compactMap({ findSaveButton($0) }).first else { fail("Save button missing") }
    press(saveButton); Thread.sleep(forTimeInterval: 0.8)
    guard let directory = ProcessInfo.processInfo.environment["RYDOOL_TEST_DATA_DIR"] else { fail("Missing test directory") }
    var savedBitmap: NSBitmapImageRep?
    for _ in 0..<25 {
        if let urls = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: nil),
           let file = urls.first(where: { $0.lastPathComponent.hasPrefix("Rydool ") && $0.pathExtension == "png" }),
           let data = try? Data(contentsOf: file), let bitmap = NSBitmapImageRep(data: data) { savedBitmap = bitmap; break }
        Thread.sleep(forTimeInterval: 0.2)
    }
    guard let bitmap = savedBitmap, bitmap.pixelsWide == 360, bitmap.pixelsHigh == 240 else { fail("Saved PNG missing or wrong size") }
    var red = 0
    for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
        if let rgb = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), rgb.redComponent > 0.8, rgb.greenComponent < 0.5, rgb.blueComponent < 0.5 { red += 1 }
    } }
    guard red > 3 else { fail("Annotations missing from saved PNG") }
    var redText = 0
    for y in (bitmap.pixelsHigh * 55 / 100)..<(bitmap.pixelsHigh * 85 / 100) { for x in (bitmap.pixelsWide * 25 / 100)..<(bitmap.pixelsWide * 80 / 100) {
        if let rgb = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), rgb.redComponent > 0.8, rgb.greenComponent < 0.5, rgb.blueComponent < 0.5 { redText += 1 }
    } }
    guard redText > 3 else { fail("Unicode text missing from saved PNG") }
    guard board.changeCount == capturedChangeCount, board.data(forType: .png) == originalPNG else { fail("Saving unexpectedly changed the clipboard") }
    board.releaseGlobally()
    print("PASS: save cancellation preserves annotations; PNG saved to isolated directory")
    exit(0)
}
guard let copy = findText(returnedOverlay, "Copy") else { fail("Copy action missing") }
press(copy); Thread.sleep(forTimeInterval: 0.6)
guard let png = board.data(forType: .png), let bitmap = NSBitmapImageRep(data: png) else { fail("PNG not copied") }
if regionMode {
    guard (214...218).contains(bitmap.pixelsWide), (142...146).contains(bitmap.pixelsHigh) else { fail("Wrong region image dimensions: \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)") }
} else {
    guard bitmap.pixelsWide == 360, bitmap.pixelsHigh == 240 else { fail("Wrong exported image dimensions") }
}
var redPixels = 0
for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide {
        if let rgb = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), rgb.redComponent > 0.8, rgb.greenComponent < 0.5, rgb.blueComponent < 0.5 { redPixels += 1 }
    }
}
guard redPixels > 3 else { fail("Arrow missing from exported PNG") }
let yRange = (bitmap.pixelsHigh * 55 / 100)..<(bitmap.pixelsHigh * 85 / 100)
let xRange = (bitmap.pixelsWide * 25 / 100)..<(bitmap.pixelsWide * 80 / 100)
var redText = 0
for y in yRange { for x in xRange {
    if let rgb = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), rgb.redComponent > 0.8, rgb.greenComponent < 0.5, rgb.blueComponent < 0.5 { redText += 1 }
} }
guard redText > 3 else { fail("Unicode text missing from copied PNG") }
board.releaseGlobally()
print("PASS: synthetic \(regionMode ? "region" : "full-screen") overlay, arrow, Unicode text, Undo, save cancellation and PNG clipboard")
