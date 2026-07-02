# Nice Shot

[![Tests](https://github.com/centimano/nice-shot/actions/workflows/tests.yml/badge.svg)](https://github.com/centimano/nice-shot/actions/workflows/tests.yml)

A lightweight, native screenshot capture and markup tool for macOS. It lives in
your menu bar, captures stills via ScreenCaptureKit, and opens a fast annotation
editor — arrows, callouts, step badges, blur, the works. Swift + SwiftUI, zero
third-party dependencies, single ~2 MB binary.

> **Made with Claude.** This project — the spec, every line of code, the app
> icon, the tests, and these docs — was written by **Claude Fable 5**,
> Anthropic's Claude Code model, working under human direction. The logic core
> and renderer are covered by 94 unit tests run on every push (see
> [TESTING.md](TESTING.md)); the capture UI is verified against a manual checklist.

## Features

- **Capture modes**: region drag-select with a live size badge and a magnifier
  loupe for pixel-perfect edges, click-to-capture window picking, full screen
  (per display), and 3/5/10-second timed capture with an on-screen countdown.
  Region captures snapshot the screen the moment the overlay opens, so the
  result is instant and exact.
- **Screen draw** (⌃⇧D): ZoomIt-style presentation mode — freeze the screen
  and draw directly on it with the editor's tools, then ⌘C to copy, ⌘S to
  save, ⌘E to keep refining in the full editor, or Esc to walk away. Single
  letters switch tools (P pen, A arrow, B box, …) just like ZoomIt.
- **Post-capture panel**: every capture pops a small floating panel — edit,
  save, copy, share, or discard. It never steals focus from what you're doing.
- **Markup editor**: arrows, lines, rectangles, ellipses, freehand pen,
  highlighter, text, speech-bubble callouts, auto-numbered step badges,
  pixelate-blur, and redact. An Office-style tool ribbon shows each tool's
  name (collapsible to compact icons). Select, move, and resize via drag
  handles; double-click to re-edit text. Full undo/redo. Crop, plus border /
  drop shadow / rounded-corner effects on export.
- **Settings** (⌘, or via the menu bar icon): record your own capture
  shortcuts, launch at login, show/hide the cursor in captures, toggle the
  shutter sound, auto-copy every capture to the clipboard, pick what happens
  after each capture (panel, copy, save, or straight into the editor), and
  either get asked where to save or quick-save into a folder of your choice.
- **Output**: PNG (default) or JPEG with a quality slider, correct DPI
  metadata for HiDPI displays, straight to the clipboard, or the macOS share
  sheet (AirDrop, Messages, Mail, …). All exports are flattened at full pixel
  resolution.

## Install

**Easiest:** grab the zip from the [latest release](https://github.com/centimano/nice-shot/releases/latest),
unzip, and drag the app to /Applications. The app isn't notarized, so on first
launch use right-click → Open (or, on newer macOS, System Settings → Privacy &
Security → **Open Anyway** after the first blocked attempt).

## Build from source

Requires macOS 14+ and the Xcode Command Line Tools (no full Xcode needed).

```bash
./build.sh                  # builds dist/Nice Shot.app
./build.sh --beta           # builds dist/Nice Shot Beta.app (separate bundle
                            # id — installs and gets permissions alongside the
                            # release app, for testing unreleased builds)
swift run NiceShotTests     # run the unit tests
```

Don't run the release and beta apps at the same time — whichever launches
second can't register the global hotkeys.

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
| Draw on screen (freeze + annotate) | ⌃⇧D |
| Timed capture (3/5/10 s) | menu bar |

All shortcuts are configurable in Settings.

In the editor: ⌘Z / ⇧⌘Z undo/redo, ⌫ deletes the selection, ⌘S saves, ⇧⌘C
copies the flattened image, Return applies a pending crop and Esc cancels it.

## Project layout

```
App/                @main entry point (thin executable)
Sources/            Library: capture pipeline, settings, panel, editor
Sources/Editor/     Annotation model, renderer, canvas, editor UI
Tests/              Unit tests (see TESTING.md)
Packaging/          Info.plist (icon is generated at build time)
Scripts/            App-icon generator
build.sh            Builds and packages dist/Nice Shot.app
```

Annotations are stored in image-pixel coordinates, and one renderer draws both
the live canvas and the exported image, so what you see is exactly what saves.

## License

MIT — see [LICENSE](LICENSE).
