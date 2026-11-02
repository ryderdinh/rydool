# Changelog

## 1.0.1 - 2026-11-02

### Screen recording

- Record a display or selected area to MP4, with optional system audio and microphone, configurable quality, and a global shortcut.

### Screenshots and appearance

- Zoom and fit screenshots in the editor.
- See a clearer selection outline, resize handles, and the output size in pixels while choosing an area.
- Drag a selection across displays. The combined image uses the highest pixel density among the selected displays.
- Use Liquid Glass for screenshot controls, menu hover highlights, and Settings navigation on macOS 26 and later.
- With Accessibility access, Rydool can intercept macOS screenshot shortcuts to avoid opening both capture tools.

### Permissions and installation

- Review Screen Recording, Accessibility, and microphone access on the new Permissions page, which opens on first launch.
- Reset an individual permission from Settings if macOS retains an old entry after reinstalling.
- The app is signed ad hoc and is not notarized; macOS may ask for permissions again after updating.

## 1.0.0 - 2026-11-01

First public release of Rydool for macOS 14 or later, supporting Apple Silicon and Intel Macs.

### Clipboard history

- Save and search copied text and images locally, with image thumbnails.
- Pin, delete, and clear items; select items with the mouse or keyboard and paste into the previous app.
- Pause monitoring and exclude selected applications from future history.

### Screenshots and annotations

- Capture a selected region or the display containing the pointer, and copy the capture to the clipboard.
- Preview, edit, copy, and save screenshots as PNG; reopen recent captures during the current session.
- Annotate screenshots with arrows, shapes, text, and freehand drawing, with undo support.

### Settings and accessibility

- Configure shortcuts, launch at login, and clipboard preferences.
- Choose English, Vietnamese, or Simplified Chinese.
- Get guidance for Screen Recording and Accessibility permissions, with manual paste available when automatic paste is unavailable.

### Installation

- Download `Rydool-macos.dmg` from the release, open it, and drag Rydool to Applications.
- This build is not notarized by Apple. If macOS blocks the first launch, choose **Open Anyway** in **System Settings → Privacy & Security**.
