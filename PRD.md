# Nice Shot — PRD (v1)

A lightweight, modern, still-image screen capture and markup app for macOS, in
the spirit of the classic capture-annotate-share desktop tools.

## Goals
- Instant capture from a menu bar icon or global hotkeys.
- After every capture, a small floating panel offers: **Edit**, **Save**, **Copy**, or discard.
- A full markup editor: arrows, shapes, text, callouts, step badges, blur/redact, crop, and border/shadow/corner effects.
- Native, fast, tiny footprint: Swift + SwiftUI + ScreenCaptureKit. No web runtime, no background services.

## Non-goals (v1)
- Video / GIF recording, scrolling capture, OCR, cloud upload, capture history library.

## App shape
- **Menu bar app** (no Dock icon, `LSUIElement`). Menu: capture modes, timed capture submenu, Settings, About, Quit.
- Editor and Settings windows open on demand; while one is open the app shows a Dock icon so ⌘-Tab works, then returns to menu-bar-only.

## Capture modes & shortcuts
| Mode | Default shortcut | Behavior |
|---|---|---|
| Region | ⌃⇧4 | Dimmed overlay, crosshair drag; live size badge; magnifier loupe with pixel coordinates; Esc cancels. The screen is snapshotted when the overlay opens, so the capture is instant and matches exactly what was on screen. |
| Window | ⌃⇧5 | Hover highlights window under cursor; click captures it cleanly |
| Full screen | ⌃⇧3 | Captures the display under the mouse (multi-monitor aware) |
| Timed | menu | 3 / 5 / 10 s countdown HUD, then full-screen capture |

All shortcuts are user-configurable in Settings (recorded live, Esc cancels
recording; global hotkeys pause while recording). Captures are full
pixel-resolution; cursor visibility is a setting (off by default). After any
overlay interaction, focus returns to the app the user was in.

## Post-capture panel
Floating, non-activating panel in the bottom-right of the capture's screen:
thumbnail + **Edit…** (prominent) / **Save** / **Copy** / ✕. Multiple captures
stack upward. Save honors the saving preference (below); a cancelled save
dialog keeps the capture. Copy puts PNG + TIFF on the clipboard.

## Settings (⌘,)
- **Shortcuts** — per-mode hotkey recorders with reset-to-default.
- **Capture** — show mouse cursor in captures.
- **Saving** — "ask where to save each time" (default) or quick-save into a
  chosen folder (default `~/Desktop`, auto-uniqued filenames).
- **General** — launch at login (`SMAppService`; works best from /Applications).

## Editor
- Toolbar: tool buttons, color picker, line weight, font size, undo/redo (⌘Z/⇧⌘Z), delete, Effects menu, Copy (⇧⌘C), Save (⌘S).
- Canvas shows the image fit-to-window at up to natural (point) size.

### Tools
1. **Select** — click to select, drag to move, drag round handles to resize
   (line/arrow endpoints, shape corners, callout tail), double-click
   text/callout to re-edit, ⌫ to remove.
2. **Arrow**, **Line**, **Rectangle**, **Ellipse** — stroke in chosen color/weight.
3. **Pen** (freehand) and **Highlighter** (wide, translucent, multiply blend).
4. **Text** — click to place, type, Return/click-away to commit; empty text is discarded.
5. **Callout** — drag a speech bubble with a movable tail; filled in chosen color with white text. Creation + typed text are one undo step.
6. **Step badge** — click to drop auto-incrementing numbered circles (1, 2, 3…).
7. **Blur** (pixelate) and **Redact** (solid black) regions.
8. **Crop** — drag region, then Return/Apply or Esc/Cancel.

### Effects (applied to the final image, previewed live)
Border (color + width), drop shadow, rounded corners.

### Export
Save as PNG (correct DPI metadata on HiDPI captures) or copy to clipboard.
Annotations are flattened at full pixel resolution.

## Permissions
Screen Recording (TCC). On first use the app preflights access, triggers the
system prompt, and offers a deep link to System Settings; macOS requires an app
relaunch after granting.

## Technical notes
- macOS 14+. Capture via `SCScreenshotManager` (ScreenCaptureKit); region/full-screen capture the display then crop; window capture uses `SCContentFilter(desktopIndependentWindow:)`.
- Global hotkeys via Carbon `RegisterEventHotKey` (no Accessibility permission needed); persisted in `UserDefaults`.
- Annotations stored in image-pixel coordinates; one SwiftUI `Canvas` renderer drives both on-screen display and `ImageRenderer` export, so WYSIWYG is exact.
- Built with SwiftPM; `build.sh` generates the icon if needed, then assembles and ad-hoc signs `dist/Nice Shot.app`.

## Future ideas
Capture history shelf, scrolling capture, annotation styles/presets,
multi-display region drag, sounds, sparse-color border themes,
share-sheet integration.
