# Rydool reimplementation work

This work replaces functionality in stages while preserving Rydool's behavior. Textual differences or passing tests alone do not establish copyright ownership.

## Work in progress

- Selection geometry and overlay chrome: replacement in progress; tests cover clamping, resizing across edges, movement, handle priority, and simulated region capture.
- Annotation model, canvas, freehand, arrow, rectangle, text layout, and image-coordinate mapping: replacement in progress; tests cover tool metadata, rendered arrows in both directions, a pen dot and stroke, rectangle drag direction, Unicode and multiline input, Retina annotation placement, and annotation undo.
- Display capture orchestration and the ScreenCaptureKit adapter: replacement in progress; fake-source tests cover retry and permission denial. A signed debug build captured the real screen with monitoring off, a temporary store, and an isolated pasteboard; the general clipboard remained unchanged. Multiple-display behavior has not been verified.
- Screen Recording permission presentation: replacement in progress; tests verify that status checks do not prompt, that the settings action requests access, and that the denied-permission explanation can be closed. The real system permission was not reset.
- Global hotkey routing, key representation, shortcut validation, and recording: replacement in progress; isolated UI tests exercised the history, region, and full-screen shortcuts using test-only key combinations, plus recording cleanup. Tests cover modifier mapping, persisted shortcut compatibility, reserved keys, system conflicts, duplicates, failed registration, and restoring other shortcuts after recording.
- Screenshot pasteboard writing and file storage: replacement in progress; named-pasteboard tests cover PNG, on-demand TIFF, and isolation from the general clipboard. Tests also cover PNG output, filename collisions, failed writes, save cancellation, and history integration.
- Settings persistence: replacement in progress; tests cover existing shortcuts, appearance settings, invalid data, default language, and language persistence. Isolated UI tests cover language switching and application exclusions.
- Login-item integration: replacement in progress; fake-service tests cover approval status, failed registration, and one-time defaults without changing the system login items. A real login has not been tested.
- Confirmation bubble and alerts: replacement in progress; the isolated capture UI test exercised copy and its confirmation. Visual appearance has not been compared across multiple displays.
- Editor toolbar: replacement in progress; isolated UI tests cover choosing tools, annotations, undo, save cancellation, and PNG export.
- Capture coordination: replacement in progress; isolated UI tests cover region capture, cancellation, preview stacking and auto-hide, saving, and taking another screenshot with an editor open. Multiple displays and cancellation while a real capture is pending have not been tested.
- Capture overlay and pointer gestures: replacement in progress; selection geometry has unit coverage, while isolated UI tests cover region selection, keyboard shortcut, editing, cancellation, save, and capture with an editor open. Multiple displays and full keyboard/VoiceOver behavior have not been verified.
- App lifecycle and main text-editing menu: replacement in progress; isolated UI tests cover clipboard shortcuts, pasting, and live language changes. Login-at-startup and clean-machine behavior remain unverified.
- Menu-bar controller and command presentation: replacement in progress; isolated UI tests cover opening the menu, capture actions, hidden preview access, prior-app paste, and language changes. The existing Rydool-designed icon animation remains.
- Settings UI: shortcut display and recording controls were restructured; isolated UI tests cover recording cleanup, excluded apps, and language selection. The rest of the settings presentation still requires provenance review.
- Bundle builder and icon generation: replaced with staged assembly and a separate icon-set writer around the Rydool-designed artwork. Tests covered a universal signed release, matching signing requirements, isolated debug launch, required bundle resources, and preserving the existing app after a signing failure. All ten generated icon sizes matched the previous artwork pixel for pixel and were accepted by iconutil. Provenance review remains necessary.

## Provenance review notes

- The current work was performed with access to the earlier implementation. It is not a clean-room implementation; restructuring the code cannot by itself establish independent authorship or justify removing attribution.
- A source comparison still finds shared fragments in areas including annotation models, capture window configuration, shortcuts, saving, and settings controls. Some consist of framework API use or ordinary declarations; each needs contextual review rather than an automatic assumption about ownership.
- `Package.swift` declares no external Swift packages. It links macOS frameworks and SQLite. The third-party license and notice were later removed at the project owner's request; this does not resolve the provenance findings.
- Earlier source history and changes should be reviewed separately when assessing provenance; the current repository starts with the present project snapshot.

## Completion checks

1. Document required user-visible behavior and replace remaining derived components with newly designed implementations, not superficial renaming or formatting.
2. Run unit and isolated UI tests for clipboard, capture, editing, shortcuts, settings, and languages; validate real capture separately and document untested configurations.
3. Audit the resulting code, dependencies, scripts, and notices for provenance. Do not claim independent authorship or remove upstream attribution based only on a similarity check.
4. Review the public Git history separately before proposing any history change; never force-push or remove it without explicit authorization.
