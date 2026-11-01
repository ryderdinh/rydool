import AppKit
import ApplicationServices
import AVFoundation
import Foundation

let app = AXUIElementCreateApplication(pid_t(Int32(CommandLine.arguments[1])!))
let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let regionMode = CommandLine.arguments.contains("--region")
let systemAudio = CommandLine.arguments.contains("--system-audio")
let microphone = CommandLine.arguments.contains("--microphone")
var expectedRegionWidth: CGFloat = 0
func fail(_ message: String) -> Never { fputs("FAIL: \(message)\n", stderr); exit(1) }
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
}
func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? [] }
func find(_ element: AXUIElement, _ text: String, role: String? = nil) -> AXUIElement? {
    let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { attribute(element, $0 as String) as? String }.joined(separator: " ")
    if label.contains(text) && (role == nil || (attribute(element, kAXRoleAttribute as String) as? String) == role) { return element }
    for child in children(element) { if let result = find(child, text, role: role) { return result } }
    return nil
}
func press(_ element: AXUIElement) { guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { fail("Cannot press control") } }
func windows() -> [AXUIElement] { attribute(app, kAXWindowsAttribute as String) as? [AXUIElement] ?? [] }
func wait(_ search: () -> AXUIElement?) -> AXUIElement? {
    for _ in 0..<40 { if let value = search() { return value }; Thread.sleep(forTimeInterval: 0.25) }
    return nil
}
guard AXIsProcessTrusted(), let raw = attribute(app, "AXExtrasMenuBar"), CFGetTypeID(raw) == AXUIElementGetTypeID(),
      let status = children(raw as! AXUIElement).first else { fail("Accessibility menu unavailable") }
let bar = raw as! AXUIElement
press(status); Thread.sleep(forTimeInterval: 0.5)
if find(bar, "Allow Screen Recording") != nil { fail("Screen Recording permission is not granted to the test app") }
guard let record = find(bar, "Record Screen") else { fail("Recording menu action missing") }
press(record)
guard let setup = wait({ windows().first { find($0, "Start recording") != nil } }) else { fail("Recording setup missing") }
if systemAudio {
    guard let toggle = find(setup, "System audio") else { fail("System audio toggle missing") }
    press(toggle)
}
if microphone {
    guard let toggle = find(setup, "Microphone") else { fail("Microphone toggle missing") }
    press(toggle)
}
if regionMode {
    guard let area = find(setup, "Selected area") else { fail("Area option missing") }
    press(area)
    guard let select = wait({ find(setup, "Select area") }) else { fail("Area selection button missing") }
    press(select); Thread.sleep(forTimeInterval: 0.6)
    let pointer = CGEvent(source: nil)?.location ?? .zero
    var display: CGDirectDisplayID = 0
    var count: UInt32 = 0
    guard CGGetDisplaysWithPoint(pointer, 1, &display, &count) == .success, count > 0 else { fail("Cannot find display") }
    let bounds = CGDisplayBounds(display)
    let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    expectedRegionWidth = bounds.width * 0.35 * (screen?.backingScaleFactor ?? 1)
    let from = CGPoint(x: bounds.minX + bounds.width * 0.1, y: bounds.minY + bounds.height * 0.1)
    let to = CGPoint(x: bounds.minX + bounds.width * 0.45, y: bounds.minY + bounds.height * 0.4)
    func mouse(_ type: CGEventType, _ point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { fail("Cannot create mouse event") }
        event.post(tap: .cghidEventTap); Thread.sleep(forTimeInterval: 0.15)
    }
    mouse(.leftMouseDown, from); mouse(.leftMouseDragged, to); mouse(.leftMouseUp, to)
} else {
    guard let start = find(setup, "Start recording") else { fail("Start recording action missing") }
    press(start)
}
// Permission prompts and stream startup may take time. The menu remains open while recording.
var stop: AXUIElement?
for _ in 0..<120 {
    press(status); Thread.sleep(forTimeInterval: 0.25)
    if let found = find(bar, "Stop recording") { stop = found; break }
    press(status); Thread.sleep(forTimeInterval: 0.25)
}
guard let stop else { fail("Recording did not start; check microphone permission") }
var tone: NSSound?
if systemAudio {
    tone = NSSound(contentsOfFile: CommandLine.arguments[3], byReference: true)
    guard tone?.play() == true else { fail("Could not play test audio") }
}
Thread.sleep(forTimeInterval: 3)
press(stop)
guard let save = wait({ windows().compactMap { find($0, "Save", role: "AXButton") }.first(where: { (attribute($0, kAXEnabledAttribute as String) as? Bool) == true }) }) else { fail("Enabled save button missing after recording") }
press(save)
var file: URL?
for _ in 0..<40 {
    file = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.pathExtension == "mp4" }
    if file != nil { break }
    Thread.sleep(forTimeInterval: 0.25)
}
guard let file else { fail("Recording was not saved in the isolated test directory") }
let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let asset = AVURLAsset(url: file)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)
        if systemAudio || microphone {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let audioTrack = audioTracks.first else { fail("System audio track missing") }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ])
            guard reader.canAdd(output) else { fail("Cannot decode system audio") }
            reader.add(output)
            guard reader.startReading() else { fail("Cannot read system audio") }
            var maxSample: Int = 0
            while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
                var data = Data(count: CMBlockBufferGetDataLength(block))
                _ = data.withUnsafeMutableBytes { bytes in
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: bytes.baseAddress!)
                }
                data.withUnsafeBytes { bytes in
                    for index in stride(from: 0, to: bytes.count - 1, by: 2) {
                        let value = Int16(bitPattern: UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8))
                        maxSample = max(maxSample, abs(Int(value)))
                    }
                }
            }
            if systemAudio && maxSample <= 20 { fail("Recorded system audio is silent") }
        }
        guard let video = tracks.first, duration.seconds >= 2 else { fail("Saved recording has no video or is too short") }
        let size = try await video.load(.naturalSize)
        if regionMode {
            guard abs(size.width - expectedRegionWidth) < 8 else { fail("Recorded area has unexpected width: \(size.width), expected \(expectedRegionWidth)") }
            let generator = AVAssetImageGenerator(asset: asset)
            let image = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB),
                  color.redComponent > 0.7, color.greenComponent < 0.35, color.blueComponent < 0.35 else {
                fail("Recorded region does not contain the selected red test area")
            }
        }
        print("PASS: recorded \(regionMode ? "region" : "screen")\(systemAudio ? " with system audio" : "")\(microphone ? " and microphone" : "") to isolated MP4 (\(String(format: "%.1f", duration.seconds)) seconds)")
        sem.signal()
    } catch { fail("Cannot read saved recording: \(error)") }
}
if sem.wait(timeout: .now() + 10) == .timedOut { fail("Timed out reading recording") }
