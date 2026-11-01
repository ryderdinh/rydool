# Rydool product behavior

This document describes observable product behavior for a future independent implementation. It was prepared from the user's requests and Rydool's current usage documentation by someone who has seen the existing source. It needs an independent review before it is used as a clean-room handoff; it is not evidence that any implementation is independently authored.

## App and settings

- Rydool is a macOS menu-bar app with clipboard history and screenshot capture. Its menu provides entry points for those functions, settings, pausing history, and quitting.
- Settings contain controls that do not need to occupy the menu. Offer English, Vietnamese, and Simplified Chinese. English is the default; changing the language takes effect immediately and persists.
- Provide configurable shortcuts for clipboard history, area capture, and full-screen capture. The requested capture defaults are Command-Shift-4 and Command-Shift-3. If a shortcut cannot be registered, inform the user and retain an alternate way to invoke the action.
- Provide a launch-at-login setting and clipboard controls, including excluded applications selected by name rather than requiring users to enter bundle identifiers.

## Clipboard history

- History monitoring is enabled by default. Allow users to pause it; paused contents should not be backfilled when monitoring resumes. History stays on the Mac.
- Display copied text and images in a searchable list with thumbnails for images. Support pinning, deleting, and clearing entries. A relative time label does not show seconds.
- Opening history by shortcut starts the list at the top. Pointer hover highlights the item under the pointer; an unrelated item must not stay visually highlighted as if hovered.
- Clicking an item once makes it the current clipboard content, moves the existing item to the top of its group without making a duplicate, closes history, and pastes into the previously focused field when the system permits it. If automatic paste is unavailable, retain the copied item and explain how to paste it manually.
- Support keyboard navigation and selection. Clicking pin or delete controls must perform that control's action rather than paste the item.

## Screenshots and preview

- Area capture shows the current screen contents while the user chooses a region; it must not replace them with a blank white screen. Full-screen capture uses the display containing the pointer. Escape cancels selection.
- Capturing immediately copies the result to the clipboard and displays a small preview in the lower-right corner. The editor toolbar does not appear during normal capture.
- The preview initially shows only the image. Hovering reveals small actions over it; clicking the image outside those actions opens a separate window with the captured image for editing. Preview actions include copy, save, edit, and close.
- The preview hides automatically after a short period. Users must have enough time to interact with it; pause its countdown while the pointer is over it or while its save dialog is open. Hidden screenshots remain accessible during the app session.
- Taking a new screenshot must work while an editor window is open, preserving the existing editor's contents. Multiple recent screenshots can be accessed independently.
- The editor supports drawing, arrows, shapes, text, undo, clipboard output, and PNG saving. Canceling a save dialog retains the editor state. Editing starts only when the user opens the preview.
- Explain Screen Recording permission when required and provide a path to system settings. Permission denial or revocation must not leave the capture interface stuck, and the user can retry after granting access.

## Verification expectations

Exercise capture, clipboard selection and paste, preview timeout and hover, editor reopening, settings persistence, and all three languages. Test permission denial and restoration, shortcut conflicts, display changes and mixed display scales. Report real hardware or system configurations that could not be tested. Automated checks must use isolated data and must not overwrite the user's clipboard or history.

## Independent implementation handoff

An independent implementer should work from a separately reviewed behavior specification, without accessing the earlier Rydool implementation, and should document the sources and dependencies actually used. The implementer's work and its provenance then need independent review before considering any license-notice change. Existing public Git history is a separate issue and is not altered by producing a new implementation.
