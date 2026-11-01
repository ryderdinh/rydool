import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class RecordingCoordinator: ObservableObject {
    static let shared = RecordingCoordinator()
    enum Phase: Equatable { case idle, preparing, recording, finishing, pendingSave }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var startedAt: Date?
    private var setup: RecordingSetupWindow?
    private var picker: RecordingAreaPicker?
    private var stream: ScreenRecordingStream?
    private var temporaryURL: URL?
    private var preparationFailure: Error?
    private init() {}

    var isBusy: Bool { phase == .preparing || phase == .recording || phase == .finishing }

    func mayQuit() -> Bool {
        if isBusy {
            Alerts.show(title: L("Recording in progress"), message: L("Stop the recording and save it before quitting."))
            return false
        }
        guard phase == .pendingSave else { return true }
        let alert = NSAlert()
        alert.messageText = L("Save recording before quitting?")
        alert.informativeText = L("The recording has not been saved yet.")
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))
        alert.addButton(withTitle: L("Discard"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            savePending()
            return phase == .idle
        case .alertThirdButtonReturn:
            if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
            temporaryURL = nil
            phase = .idle
            return true
        default: return false
        }
    }

    func showSetup() {
        guard phase == .idle else {
            if phase == .pendingSave { savePending() }
            return
        }
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        let testSetup = env["RYDOOL_TEST_RECORDING_SETUP"] == "1" && env["RYDOOL_TEST_DATA_DIR"] != nil && env["RYDOOL_TEST_DEFAULTS"] != nil && env["RYDOOL_TEST_PASTEBOARD"] != nil
        #else
        let testSetup = false
        #endif
        guard ScreenAccess.isGranted || testSetup else { PermissionWindowController.shared.show(); return }
        let setup = RecordingSetupWindow { [weak self] options in self?.chooseArea(options) }
        self.setup = setup
        setup.show()
    }

    private func chooseArea(_ options: RecordingOptions) {
        setup = nil
        guard phase == .idle else { return }
        if options.area {
            phase = .preparing
            let picker = RecordingAreaPicker()
            self.picker = picker
            picker.show(on: options.screen) { [weak self] selection in
                guard let self else { return }
                self.picker = nil
                guard let selection else { self.phase = .idle; return }
                self.begin(options, selection: selection)
            }
        } else { begin(options, selection: options.screen.frame) }
    }

    private func begin(_ options: RecordingOptions, selection: CGRect) {
        guard let id = options.screen.displayID,
              let geometry = RecordingGeometry(screenFrame: options.screen.frame, selection: selection,
                                               scale: options.screen.backingScaleFactor) else {
            phase = .idle
            Alerts.show(title: L("Couldn't start recording"), message: L("Select a valid area and try again."))
            return
        }
        phase = .preparing
        preparationFailure = nil
        Task { @MainActor in
            if options.microphone {
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                let allowed = status == .authorized ? true : status == .notDetermined ? await AVCaptureDevice.requestAccess(for: .audio) : false
                guard allowed else {
                    phase = .idle
                    Alerts.show(title: L("Microphone access required"), message: L("Allow microphone access in System Settings, or turn off the microphone."))
                    return
                }
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Rydool-\(UUID().uuidString).mp4")
            temporaryURL = url
            do {
                let recording = try await ScreenRecordingStream.start(displayID: id, geometry: geometry, outputURL: url,
                    systemAudio: options.systemAudio, microphone: options.microphone) { [weak self] error in
                        Task { @MainActor in self?.streamFailed(error) }
                    }
                stream = recording
                startedAt = Date()
                phase = .recording
                if let error = preparationFailure {
                    preparationFailure = nil
                    streamFailed(error)
                }
            } catch {
                try? FileManager.default.removeItem(at: url)
                temporaryURL = nil
                phase = .idle
                Alerts.show(error)
            }
        }
    }

    func stop() {
        guard phase == .recording, let stream else { return }
        phase = .finishing
        startedAt = nil
        Task { @MainActor in
            do {
                try await stream.stop()
                self.stream = nil
                phase = .pendingSave
                savePending()
            } catch {
                self.stream = nil
                // Preserve any partial file for manual recovery rather than silently deleting it.
                let location = temporaryURL?.path ?? ""
                phase = .idle
                temporaryURL = nil
                Alerts.show(title: L("Couldn't finish recording"), message: "\(error.localizedDescription)\n\(location)")
            }
        }
    }

    private func streamFailed(_ error: Error) {
        if phase == .preparing { preparationFailure = error; return }
        guard phase == .recording else { return }
        stop()
        Alerts.show(title: L("Recording interrupted"), message: error.localizedDescription)
    }

    func savePending() {
        guard phase == .pendingSave, let source = temporaryURL else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "Rydool \(Date().formatted(date: .numeric, time: .shortened).replacingOccurrences(of: "/", with: "-")) .mp4"
        panel.directoryURL = AppSettings.shared.lastSaveDirectory
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            // Write via the save panel destination; retain the temporary original on failure.
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: source)
            } else { try FileManager.default.moveItem(at: source, to: destination) }
            AppSettings.shared.lastSaveDirectory = destination.deletingLastPathComponent()
            temporaryURL = nil
            phase = .idle
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch { Alerts.show(error) }
    }
}
