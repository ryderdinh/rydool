# Rydool

Rydool is a macOS menu bar app for clipboard history, screenshots, and annotations. It is under development; see the [implementation plan](docs/rydool-plan.md) and [verification status](docs/verification.md).

## Download

Download `Rydool-macos.dmg` from the [latest release](https://github.com/ryderdinh/rydool/releases/latest), open it, and drag Rydool to Applications. The app supports macOS 14 or later on Apple Silicon and Intel Macs.

The release is signed ad hoc and is not notarized by Apple. If macOS blocks the first launch, open **System Settings → Privacy & Security** and choose **Open Anyway** for Rydool, then confirm. You may need to grant Screen Recording and Accessibility permissions for capture and automatic pasting.

See the [changelog](CHANGELOG.md) for release notes.

## Build and run

Requirements: macOS 14 or later and Xcode 16.2 (or equivalent Command Line Tools). From the project directory:

```sh
swift test
Scripts/build-app.sh debug
open build/Rydool.app
```

To package a release DMG locally, install `dmgbuild==1.6.6` in a Python environment, then run `Scripts/build-app.sh release` followed by `DMG_PYTHON=/path/to/python Scripts/package-dmg.sh`.

Run interactive UI tests with simulated data (requires a desktop session and Accessibility permission for the test process):

```sh
python3 Tests/UI/run-smoke.py
python3 Tests/UI/run-capture-smoke.py --region
python3 Tests/UI/run-capture-smoke.py --save
```

These tests use a separate pasteboard and database and temporarily control the mouse and keyboard to interact with the UI. Simulated data mode is available only in debug builds.

By default, the build script creates a universal binary for Apple Silicon and Intel. If exactly one valid Apple Development identity is available, the script uses it to keep the signature stable across builds; otherwise, it signs ad hoc. Set `ARCHS=arm64` to build only for Apple Silicon, or `RYDOOL_SIGN_IDENTITY` to choose an identity (`-` means ad hoc). Builds are not notarized, so macOS may require permission to open them in Privacy & Security. Screen Recording permission may need to be granted again after changing the signing identity or using an ad hoc build. Open the `.app` bundle in Finder or with `open`, as above; running the executable inside `Contents/MacOS` directly from VS Code can cause macOS to attribute the permission request to VS Code instead of Rydool.

## Usage

Open Rydool from its menu bar icon. Clipboard history is **enabled** by default and stores content copied after the app starts on the local machine. You can pause it from the menu or Settings; the pause state persists across restarts. Open history with `⌥⇧V`, search for text, and click an item once or select it with the arrow keys and Enter to close history and paste into the previously active app. The item moves to the top of its pinned or unpinned group without creating a duplicate. macOS may require Accessibility permission for automatic pasting; without it, the item is still copied so you can paste manually with `⌘V`. Use the buttons beside an item to pin or delete it. Clear All also deletes pinned items.

Press `⌘⇧4` to capture a region or `⌘⇧3` to capture the entire display containing the pointer. The image is automatically copied to the clipboard immediately after capture. A preview appears in the lower-right corner and hides after five seconds; the countdown pauses while the pointer is over it or a save dialog is open. Click the preview to open the editor. Hover over it to reveal buttons to edit, copy, save a PNG, or close the preview. Multiple screenshots can be captured in succession; their previews are arranged side by side.

While the app is running, hidden previews can be reopened using **Recent Screenshots** in the Rydool menu. Images are held only in memory: use **Copy** or **Save** before quitting if you want to keep them. The `×` button removes an image from this list.

In the editor, use the toolbar to add arrows, shapes, text, or freehand strokes. Press Shift+Enter for a new line while entering text; Enter or Copy puts the image on the clipboard, Save opens a PNG dialog, and Esc cancels editing and returns to the preview. You can capture another screenshot while the editor is open; edits remain in that window. macOS requires Screen Recording permission for capture, and the app guides you through it the first time.

Choose **Record Screen** from the menu bar or press `⌃⌥⇧R` to configure a screen recording. Select a display and either the full screen or an area, and optionally enable system audio or the microphone. System audio is on by default; the microphone is off. Recordings target up to 60 frames per second, depending on the display and system performance. A red indicator in the menu bar marks an active recording; select **Stop recording** or press the shortcut again to finish. Choose where to save the MP4 file. If you cancel the save dialog, select **Save recording…** from the menu to save it later. Rydool asks for microphone permission only when microphone recording is enabled. The shortcut can be changed under Settings → Shortcuts.


Choose **Settings…** from the menu to open the settings window. Under **General → Language**, choose English (the default), Vietnamese, or Simplified Chinese; the change takes effect immediately and is remembered. macOS-provided dialogs may use the system language. Under Clipboard, choose **Add application…** to select an app to exclude; use the minus button beside its name to remove it. Exclusions apply to future copies, and the source app is inferred from the foreground window. Default capture shortcuts may conflict with other apps or macOS screenshot shortcuts. If registration fails, use the menu, choose different shortcuts, or release the shortcuts in the other app. Previously customized shortcuts are preserved.

## Data and privacy limitations

History is stored in SQLite at `~/Library/Application Support/Rydool/`. Rydool does not separately encrypt the content, and it may be included in backups. Skipping common sensitive markers and excluded apps is a safeguard and **does not guarantee detection of every password**. The source app is inferred from the foreground app and may be wrong, especially for clipboard content from another device or a background task. Pause monitoring when you do not want to record content; the app does not save clipboard content that was already present before monitoring was enabled or resumed. Deletion is logical deletion and does not guarantee secure erasure from SSDs or backups. Polling may miss copies made too quickly; if the processing queue is full, the app skips new items and notifies you.

The current version stores plain text and images, not rich text or files. The storage quota measures saved content; the actual size of SQLite, WAL, and thumbnail files may be larger. There is no cloud sync or account.

## License

Copyright © 2026 ryderdinh. Rydool is available under the [MIT License](LICENSE).
