# Nice Shot

[![Tests](https://github.com/centimano/nice-shot/actions/workflows/tests.yml/badge.svg)](https://github.com/centimano/nice-shot/actions/workflows/tests.yml)

A lightweight, native screenshot capture and markup tool for macOS. It lives in
your menu bar, captures stills via ScreenCaptureKit, and opens a fast annotation
editor — arrows, callouts, step badges, blur, the works. Swift + SwiftUI, zero
third-party dependencies, single ~2 MB binary.

> **Made with Claude.** This project — the spec, every line of code, the app
> icon, the tests, and these docs — was written by **Claude Fable 5**,
> Anthropic's Claude Code model, working under human direction. The logic core
> and renderer are covered by unit tests run on every push (see
> [TESTING.md](TESTING.md)); the capture UI is verified against a manual checklist.
>
> With v2 — screen draw, frozen zoom, and board modes — the original vision is
> complete. *Claude takes a bow.* 🎩 v2.2's security and performance pass and
> the capture tray were also made with Claude Code.

## Features

- **Capture modes**: region drag-select with a live size badge and a magnifier
  loupe for pixel-perfect edges, click-to-capture window picking, full screen
  (per display), and 3/5/10-second timed capture with an on-screen countdown.
  Region captures snapshot the screen the moment the overlay opens, so the
  result is instant and exact.
- **Screen draw** (⇧⌘D): ZoomIt-style presentation mode — freeze the screen
  and draw directly on it with the editor's tools, then ⌘C to copy, ⌘S to
  save, ⌘E to keep refining in the full editor, or Esc to walk away. Single
  letters switch tools (P pen, A arrow, B box, …) just like ZoomIt. W and K
  swap the frozen screen for a whiteboard or blackboard when you'd rather
  sketch on a clean surface.
- **Frozen zoom** (⇧⌘Z): freeze the screen and magnify up to 8× — scroll or
  arrow keys zoom toward the cursor, moving the mouse pans, and ⌘C/⌘S/⌘E
  export exactly what's on screen. Press any drawing key to annotate the
  magnified view; double-click or Esc exits.
- **Post-capture panel**: every capture pops a small floating panel — edit,
  save, copy, share, or discard. It never steals focus from what you're doing.
- **Capture tray**: take another shot while the panel is still up and both
  move into one tray instead of stacking separate panels. Each capture gets
  its own row of actions, plus Save All / Discard All, and the tray folds
  down to a small "N Captures" stack when you want it out of the way.
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

Every pull request also builds a ready-to-run **Nice Shot Beta.app** on
GitHub: open the PR's *Checks* → *Tests* run and download **Nice-Shot-Beta**
under *Artifacts*. To publish a version, bump it in `Packaging/Info.plist`,
add its notes to `CHANGELOG.md`, merge to `main`, then run **Actions →
Release → Run workflow**. It tests, builds, and publishes the release with the
zip attached.

Don't run the release and beta apps at the same time — whichever launches
second can't register the global hotkeys.

Move the app to `/Applications` if you want **Launch at login** to work
reliably. The bundle is ad-hoc signed, so Gatekeeper on another Mac will warn
on first open (right-click → Open).

### Privacy & security

- Everything stays on your Mac: no network access, no analytics, no
  accounts. Captures go only where you send them (clipboard, a file, or the
  share sheet).
- Signed with Apple's hardened runtime. Not notarized (that needs a paid
  Apple Developer account), hence the first-launch Gatekeeper prompt.
- Images staged for the share sheet live in a private temporary folder that
  is cleaned up automatically; quick-save never overwrites an existing file.

### Permissions

The first capture triggers the **Screen Recording** permission prompt. Grant it
in System Settings → Privacy & Security → Screen & System Audio Recording, then
relaunch the app — a one-time macOS requirement.

## Usage

| Action | Default shortcut |
|---|---|
| Capture region (drag, Esc cancels) | ⇧⌘S |
| Capture window (hover + click) | ⇧⌘W |
| Capture full screen (display under mouse) | ⇧⌘F |
| Draw on screen (freeze + annotate) | ⇧⌘D |
| Zoom into screen (freeze + magnify) | ⇧⌘Z |
| Timed capture (3/5/10 s) | menu bar |

All shortcuts are configurable in Settings.

In the editor: ⌘Z / ⇧⌘Z undo/redo, ⌫ deletes the selection, ⌘S saves, ⇧⌘C
copies the flattened image, Return applies a pending crop and Esc cancels it.

## Project layout

```
App/                @main entry point (thin executable)
Sources/            Library: capture pipeline, settings, panel & tray, editor
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
