import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Rydool

private final class FakeShortcutEnvironment: ShortcutRecordingEnvironment {
    var combos: [ShortcutCaptureController.Action: ShortcutBinding] = [
        .region: .default, .history: .historyDefault, .fullScreen: .fullScreenDefault, .screenRecording: .recordingDefault
    ]
    var registered: [ShortcutCaptureController.Action: ShortcutBinding] = [:]
    var reject: ShortcutBinding?
    var validation: ShortcutValidation = .ok
    func current(for action: ShortcutCaptureController.Action) -> ShortcutBinding { combos[action]! }
    func save(_ combo: ShortcutBinding, for action: ShortcutCaptureController.Action) { combos[action] = combo }
    func register(_ combo: ShortcutBinding, for action: ShortcutCaptureController.Action) throws {
        if combo == reject { throw GlobalHotkeyManager.RegistrationError.alreadyInUse }
        registered[action] = combo
    }
    func unregister(_ action: ShortcutCaptureController.Action) { registered[action] = nil }
    func validate(_ combo: ShortcutBinding) -> ShortcutValidation { validation }
}

final class ShortcutRecorderBehaviorTests: XCTestCase {
    func testDuplicateDoesNotReplaceStoredShortcut() {
        let env = FakeShortcutEnvironment()
        let recorder = ShortcutCaptureController(.region, environment: env)
        recorder.apply(.historyDefault)
        XCTAssertEqual(env.current(for: .region), .default)
        XCTAssertEqual(recorder.message?.kind, .error)
        XCTAssertTrue(env.registered.isEmpty)
    }

    func testFailedRegistrationRestoresPreviousShortcut() {
        let env = FakeShortcutEnvironment()
        let replacement = ShortcutBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: [.command, .option])
        env.reject = replacement
        let recorder = ShortcutCaptureController(.region, environment: env)
        recorder.apply(replacement)
        XCTAssertEqual(env.current(for: .region), .default)
        XCTAssertEqual(env.registered[.region], .default)
        XCTAssertEqual(recorder.message?.kind, .error)
    }

    func testSuccessfulRecordingRestoresOtherActionsAndSavesNewKey() {
        let env = FakeShortcutEnvironment()
        let replacement = ShortcutBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: [.command, .option])
        let recorder = ShortcutCaptureController(.region, environment: env)
        recorder.start()
        recorder.apply(replacement)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(env.current(for: .region), replacement)
        XCTAssertEqual(env.registered[.region], replacement)
        XCTAssertEqual(env.registered[.history], .historyDefault)
        XCTAssertEqual(env.registered[.fullScreen], .fullScreenDefault)
        XCTAssertEqual(env.registered[.screenRecording], .recordingDefault)
    }
}
