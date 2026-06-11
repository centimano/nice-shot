# Super Duper Screenshot

A lightweight, native screenshot capture and markup tool for macOS. It lives in
your menu bar, captures stills via ScreenCaptureKit, and opens a fast annotation
editor — arrows, callouts, step badges, blur, the works. Swift + SwiftUI, zero
third-party dependencies, single ~2 MB binary.

> **Made with Claude.** This project — the spec, every line of code, the app
> icon, and these docs — was written by **Claude Fable 5**, Anthropic's Claude
> Code model, working under human direction. Treat it accordingly: it has been
> exercised by hand but has no automated test suite yet.

## Features

- **Capture modes**: region drag-select (with live size badge), click-to-capture
  window picking, full screen (per display), and 3/5/10-second timed capture
  with an on-screen countdown.
- **Post-capture panel**: every capture pops a small floating panel — edit,
  save, copy, or discard. It never steals focus from what you're doing.
- **Markup editor**: arrows, lines, rectangles, ellipses, freehand pen,
  highlighter, text, speech-bubble callouts, auto-numbered step badges,
  pixelate-blur, and redact. Select, move, and resize via drag handles;
  double-click to re-edit text. Full undo/redo. Crop, plus border / drop
  shadow / rounded-corner effects on export.
- **Settings** (⌘, or via the menu bar icon): record your own capture
  shortcuts, launch at login, show/hide the cursor in captures, and either get
  asked where to save or quick-save into a folder of your choice.
- **Output**: PNG with correct DPI metadata for HiDPI displays, or straight to
  the clipboard. All exports are flattened at full pixel resolution.

## Install & build

Requires macOS 14+ and the Xcode Command Line Tools (no full Xcode needed).

```bash
./build.sh                              # builds dist/Super Duper Screenshot.app
open "dist/Super Duper Screenshot.app"
```

Move the app to `/Applications` if you want **Launch at login** to work
reliably. The bundle is ad-hoc signed, so Gatekeeper on another Mac will warn
on first open (right-click → Open).

### Permissions

The first capture triggers the **Screen Recording** permission prompt. Grant it
in System Settings → Privacy & Security → Screen & System Audio Recording, then
relaunch the app — a one-time macOS requirement.

## Usage

| Action | Default shortcut |
|---|---|
| Capture region (drag, Esc cancels) | ⌃⇧4 |
| Capture window (hover + click) | ⌃⇧5 |
| Capture full screen (display under mouse) | ⌃⇧3 |
| Timed capture (3/5/10 s) | menu bar |

All shortcuts are configurable in Settings.

In the editor: ⌘Z / ⇧⌘Z undo/redo, ⌫ deletes the selection, ⌘S saves, ⇧⌘C
copies the flattened image, Return applies a pending crop and Esc cancels it.

## Project layout

```
Sources/            App, capture pipeline, settings, post-capture panel
Sources/Editor/     Annotation model, renderer, canvas, editor UI
Packaging/          Info.plist (icon is generated at build time)
Scripts/            App-icon generator
build.sh            Builds and packages dist/Super Duper Screenshot.app
```

Annotations are stored in image-pixel coordinates, and one renderer draws both
the live canvas and the exported image, so what you see is exactly what saves.

## License

MIT — see [LICENSE](LICENSE).
