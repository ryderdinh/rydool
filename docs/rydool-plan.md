# Rydool — MVP implementation plan

Status: **original plan; implementation in progress**. Updated November 1, 2026. See [verification status](verification.md) for what has and has not been verified.

This historical plan predates later product decisions, including automatic pasting and the screenshot preview flow. See the [README](../README.md) for current usage.

**Current implementation difference:** image content is stored as BLOBs in SQLite alongside metadata instead of separate asset files. This enables atomic insert/delete/quota transactions and avoids orphaned files. Lists load only thumbnails; original image data is read only when copying. The quota measures payload size, excluding SQLite/WAL files and thumbnails, so disk usage can exceed the limit. The stages, assumptions, and criteria below remain a plan, not evidence of completion.

## 1. Product goals and assumptions

Rydool is a macOS menu bar app combining clipboard history with screenshots and annotations. After capturing, users can copy and paste an image and find it again in history.

MVP goal: one person can use both tools daily on their own machine without an account or cloud service. The defaults below are **proposals subject to change**, not requirements finalized by the user.

| Decision | MVP proposal |
|---|---|
| Platform | Native macOS 14 or later, Swift, SwiftUI + AppKit; support Apple Silicon and Intel where the build environment permits |
| Distribution | Manually installed test build outside the App Store; decide the official channel once the MVP is stable |
| Data | Local to the machine; no account, sync, analytics, or network upload of content |
| Clipboard | Plain text and images; selecting an item copies it again, with no automatic paste |
| Screenshot | Select a region on one display or capture one whole display; a preview in the corner opens the editor or allows copying or saving PNG |
| History default | At most 200 **unpinned** items; pinned items are not removed by the item-count limit |
| Permissions | Request Screen Recording only when screenshot capture is first used; Accessibility is not needed without automatic paste |

Outside the MVP: OCR, video/GIF recording, scrolling capture, smart window capture, selection spanning multiple displays, blur, cloud, share links, sync, automatic paste, file/rich-text history, extensions/plugins, accounts, and automatic updates. These belong in the backlog and are not MVP completion criteria.

## 2. User flows

### 2.1 First launch

1. The app appears in the menu bar; its menu includes **Clipboard History**, **Capture Area**, **Capture Full Screen**, **Settings**, **Pause/Resume**, and **Quit**.
2. At the user's request, clipboard monitoring is enabled by default. Settings explains that data is stored locally and may contain sensitive content. Users can pause it, and that choice persists across restarts.
3. Settings lets users view/change shortcuts, enable launch at login, clear history, set limits, exclude apps, and check permissions. Launch at login is disabled by default.
4. Default shortcuts are `⌥⇧V` for history, `⌘⇧4` for a region, and `⌘⇧3` for full screen. On registration failure, show the reason and allow changes. The menu remains a fallback.

### 2.2 Clipboard

1. While monitoring is enabled, the user copies text or an image; valid items appear at the top of history. Do not save content already on the clipboard before monitoring was enabled or resumed: record only subsequent changes.
2. Open history through the shortcut or menu. The popup has a search field, newest-first list, pinned group, and empty/paused states. Text shows a preview; images have thumbnails. Use up/down and Enter to copy again; Escape closes the popup.
3. Selecting an item writes it to the clipboard and closes the popup; the user presses `⌘V` manually. Pin/unpin and delete individual items in the UI; provide a confirmed Clear All action that includes pinned items.
4. Search applies only to stored text; there is no image OCR. Show a clear no-results state.

### 2.3 Screenshot

1. The user chooses region or full-screen capture. If permission is missing, explain why and show the system prompt/settings; denial or revocation must not hang the app and the user can retry.
2. Region: show overlays on displays; drag a selection within **one** display, or press Escape to cancel. Full screen: use the display containing the pointer at activation; report an error if the display disappears.
3. On the captured image, the user draws arrows/rectangles, adds text, chooses basic colors/widths, and undoes the last operation. The original image remains unchanged until export.
4. **Copy** writes the annotated image to the clipboard; **Save** opens a PNG save dialog, and canceling it keeps the editor open; **Cancel** exits without writing. Saving alone does not copy the image. After copying, if monitoring is enabled and the item is not excluded, history receives exactly one image.
5. If a display changes during capture, permission is lost, or export fails, close or retain the editor as appropriate and explain the recovery action; do not write incorrect data or falsely report success.

## 3. Functional scope and rules

### Clipboard and privacy

- Monitor `NSPasteboard.general.changeCount` with an internally configurable timer, initially proposed at 0.5 seconds. Polling is best effort and may miss very rapid copies; do not promise to record every event.
- Read metadata and data types before content. Skip pasteboard types marked transient, confidential, or excluded from history by the source app and test with fixtures. Detection of every password cannot be guaranteed; explain this limitation in Settings.
- Exclusions use the bundle ID of the app in the foreground when a change is detected. This is an **inference**, not proof of the clipboard's actual source, especially with Universal Clipboard and background tasks. When exclusions are configured and the foreground app cannot be identified, skip that copy. Documentation must explain the limitation and allow pausing.
- Store only UTF-8 text and images that can be decoded to PNG. Ignore other formats; do not claim to preserve rich text or files. For multiple representations of one copy, prefer a valid image, otherwise use text, and save one item. Test pasteboards containing multiple items and limit data before decoding.
- Proposed limits: 1 MB per text item, 20 MB of encoded data per image, and 100 million pixels. Skip items exceeding the limits without partial storage; show a short notification without sensitive content. Validate the thresholds with real tests.
- Deduplicate using a hash of the type and exact normalized data: copying duplicate content moves the existing item to the top and retains its pinned state; do not merge text that differs in whitespace. Compare data before merging in the event of a hash collision.
- When a user reselects an item, mark the internal clipboard write using the post-write `changeCount` and ignore exactly that change; do not skip an external copy that follows. A new screenshot enters the same pipeline as an external copy and is recorded once. Test this definition with successive copies.
- At the item-count quota, remove the oldest unpinned item after a successful write. If all items are pinned, a new item can still be added within the unpinned quota. A separate total-history size limit of 500 MB is proposed; if pinned items prevent enough space from being freed, reject the new item and notify the user rather than silently deleting pinned items. Apply a reduced quota immediately and explain how many items may be removed.
- Pausing stops reading and recording new content. On resume, use the current `changeCount` as a baseline and do not backfill items copied while paused. Disabled monitoring persists across restarts; do not log content, thumbnails, image paths, or search terms.

### Screenshot and editor

- Use ScreenCaptureKit to obtain the original image for each display. The overlay identifies the display and rectangle in **points**, converts to pixels using the actual image scale, and clamps to the bounds. Do not assume displays share a scale, have positive coordinates, or start at the desktop origin.
- Store annotation geometry in coordinates relative to the selected image; render once into a bitmap at the original resolution. Provide default color/width and three tools; Unicode, newlines, and Vietnamese characters must render correctly.
- Keep annotations in order; undo removes the latest completed operation without changing the original. Support Escape and Enter/Copy while not editing text; operations must not consume text input keys.
- Export PNG at the selection's exact pixel dimensions. Test unannotated originals, display edges, 1x/2x displays, and multiple displays. Handle denied permission, no display, render failure, disk exhaustion, and save-panel cancellation separately.

### Settings

- Manage shortcuts for three actions; validate combinations, attempt registration before saving, and roll back to the old shortcut if it fails. Explain that not all conflicts with other apps can be detected.
- Provide monitoring, launch at login, item-count/storage quotas, excluded apps, Clear History, and a default screenshot save path if quick save is added later. The MVP uses a save panel and does not require a default path.
- Persist settings and apply changes immediately. When the system denies a login item, show the actual state and how to open System Settings. Describe privacy and the lack of automatic paste in the app.

## 4. Architecture and data design

The app is a single process divided into modules by responsibility; a plugin architecture is not yet needed:

```text
Menu bar / Settings / History popup / Capture overlay
                    │
                AppCoordinator
             ┌──────┴───────┐
      ClipboardService   CaptureService ── Annotation renderer
             │                  │
      HistoryRepository    Clipboard writer / PNG exporter
             │
         SQLite + local asset store
```

| Component | Responsibility |
|---|---|
| AppCoordinator | Lifecycle, menu bar, shortcuts, window and state coordination |
| ClipboardService | Polling, skipped types/apps, limits, deduplication, and marking internal writes |
| HistoryRepository | Search/pin/delete, transactions, ordering, quotas, and failure recovery |
| AssetStore | Write/read/delete images in Application Support; generate filenames internally and do not trust paths from external data |
| CaptureService | Permissions, display list, capture, and overlay coordination |
| AnnotationRenderer | Geometry model, undo, bitmap rendering at the correct scale, and PNG export |
| Settings/Shortcut | Persist settings, register shortcuts, and track launch status |

Store a SQLite database and `assets/` directory at `~/Library/Application Support/Rydool/`; the exact path may change if sandboxing or the distribution channel requires it. Proposed schema: `history_item(id, kind, created_at, last_copied_at, pinned_at, content_hash, text_content, image_asset_id, image_bytes, source_bundle_id)`; only one of text/asset has a value. Add schema versioning/migrations and indexes by time, pin, and hash. `source_bundle_id` is only an inferred foreground app and may be null; do not treat it as an accurate security signal.

Serialize writes and quota operations through a queue or actor; use SQLite transactions for metadata. Write new assets temporarily, verify them, then atomically rename before committing metadata; on failure, roll back and remove new assets. Delete metadata in a transaction, then remove assets after commit. On startup, clean up orphans and handle missing assets with a notification or removal of corrupt records under a clear policy. Do not lose existing items when a new write fails. Thumbnails can be regenerated and are not source data. Clear All includes associated assets; do not claim secure erasure on SSDs or backups.

Do not log clipboard content. Local data is not separately encrypted by the app by default. macOS, backups, and anyone with access to the account may access the data. FileVault is an optional user choice, not a guarantee provided by the app.

## 5. Technology and references

- AppKit for pasteboard, menus/windows, and system interaction; SwiftUI for settings and suitable UI. [Apple: NSPasteboard and changeCount](https://developer.apple.com/documentation/appkit/nspasteboard/changecount) describes how the counter changes with pasteboard ownership.
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) for screenshots. Verify permissions and actual behavior on each supported macOS version.
- SQLite through an API/library selected after the spike; favor a solution compatible with the toolchain and easy to migrate. No dependency or version is locked yet. Use [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) for the login item and check system status and errors.
- When copying or modifying third-party code, review its license and retain any required copyright and license notices. Record sources and dependencies used.

## 6. Implementation roadmap

Estimates assume **one developer familiar with Swift/macOS**, working nearly full time. These are estimated working days, not a commitment: **18–27 days** total plus **3–5 days of contingency**. The stages can change after the spike.

| Stage | Work | Deliverable and exit condition | Estimate |
|---|---|---|---|
| 0. Spike | Select toolchain/SDK and shortcut/SQLite versions; try app bundle builds, screenshot permission, two displays/scales, and test signing | Document the solution, limitations, and dependency decisions; do not block clipboard work if an external display is unavailable | 2–3 days |
| 1. App shell | Create the project, menu bar, lifecycle, Settings, three shortcuts and registration status; basic CI build | Stable launch/quit, settings survive restart; shortcut errors are reported with a menu fallback | 2–3 days |
| 2. History | ClipboardService, repository/schema, text/images, quota, deduplication, search/pin/delete, popup, and keyboard | Complete flow 2.2; data survives restart and images are deleted with records | 5–7 days |
| 3. Privacy | Pause, sensitive types, app exclusions, size limits, and storage errors | Test pause/resume, sensitive markers, unknown sources, and quotas; do not log content | 2–3 days |
| 4. Capture | Permission UX, region/full-screen capture, overlay, multiple displays/scales, cancel, and basic export | Accurate selection pixels and working copy/save on tested configurations; no crash on permission denial | 3–5 days |
| 5. Editor and integration | Arrows, text, shapes, color/width, undo, PNG, and adding images to history | Capture → annotate → copy → find the image works without duplicates or loops | 3–4 days |
| 6. Polish | Test matrix, fixes, login item, UI accessibility, packaging, and trial instructions | Section 8 criteria met; serious issues fixed or documented; reproducible installable test build | 1–2 days |

Dependencies: stage 1 precedes the UI work; stage 2 precedes integration in stage 5; stage 3 must be complete before a trial with real data; stage 4 precedes stage 5. If the spike reveals high multiple-display risk, prioritize it in stage 0 rather than silently dropping the external-display requirement.

## 7. Test strategy

- **Unit:** identification of skipped types, deduplication and collisions, quota with pinned items, empty/oversized input, migrations, coordinates and scale, annotation/undo. Use fake pasteboard/clock/display implementations to reproduce edge cases; do not put personal data in fixtures.
- **Integration:** real SQLite and assets in temporary directories; copy text/images, restart, search/pin/delete/clear, write failures and recovery of orphans/records with missing files; internal clipboard writes do not loop; a new screenshot creates exactly one item; consecutive clipboard changes during polling.
- **Manual on macOS:** test two supported versions if machines or VMs are available; one display and external 1x/2x displays, positioned left/right/above/below and changed during capture. If hardware is unavailable, record **not tested** rather than marking it passed.
- **Permissions and UX:** missing/denied/regranted/revoked Screen Recording; cancel selection/save panel; conflicting shortcut changes, denied login item; full keyboard operation of clipboard history; VoiceOver and basic contrast.
- **Stability:** pause while copying, force-quit during writes, disk exhaustion, large images, background operation, and repeated copies. Measure actual CPU/memory instead of making unmeasured performance commitments. Test PNG by comparing pixel dimensions and region content, including Vietnamese annotations.
- **Build/trial release:** clean build from source and locked dependencies; run automated tests; verify bundle/signing and Gatekeeper experience on a clean machine. Test Apple Silicon and Intel where environments are available; explicitly record configurations not tested.

## 8. MVP completion criteria

1. The menu bar app runs on supported macOS versions; menu and shortcuts open the correct functions, settings survive restart, and shortcut/login errors are reported.
2. Monitoring is enabled by default and can be paused; copying text/images, text search, keyboard selection to copy again, pin/unpin, and deletion work; there is no automatic paste.
3. Item-count and storage quotas, Clear All, pause/resume, skipped markers, and exclusions work according to section 3; content/source detection limits are explained.
4. Region or full-display capture works on the primary and external displays, including differing scales; exit/cancel and permission changes do not cause instability.
5. Arrows, shapes, text, and undo export PNG at the correct pixel dimensions; copying or saving succeeds, canceling save does not lose edits, and a copied image appears exactly once in history when monitoring is enabled.
6. Test and build results from section 7 are recorded; untested configurations are clearly identified and not marked as passed. No data-loss or content-in-log bugs remain in tested flows.
7. Provide instructions for installation, granting permissions, pausing/clearing history, and security limitations, as well as notices for code/libraries actually used.

## 9. Risks and open decisions

| Risk / question | Handling before or during implementation |
|---|---|
| Password manager does not set a marker, or source app is inferred incorrectly | Skip known markers, provide pause/exclusions, explain limitations, and test real apps without promising absolute protection |
| Polling misses rapid copies | Accept best effort for the MVP; measure and adjust the polling interval without promising every copy |
| Complex Retina/multiple-display coordinates | Spike and test on real hardware, including negative display coordinates; do not support selections spanning displays in the MVP |
| Reference source code brings many dependencies | Reuse only ideas or integrable portions, record source/license, keep separate APIs, and verify builds before committing to a library |
| Toolchain and signing | Choose the Xcode version in the spike; stable signing may be needed to test permissions, with Developer ID/notarization depending on the official distribution channel |
| Mac App Store or website distribution | Initially plan a manual test build; decide before configuring entitlements, sandboxing, release signing, and automatic updates |
| Minimum macOS 14 / Intel build | These are assumptions based on references; confirm demand and test infrastructure before announcing support |
| UI/branding, shortcuts, and quotas | Defaults in this document are proposals and may change after user feedback without changing the MVP goal |
