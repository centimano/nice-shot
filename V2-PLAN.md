# Nice Shot v2 — ZoomIt-inspired live screen modes

Planned 2026-07-02. Goal: bring the useful parts of Sysinternals ZoomIt to
Nice Shot as a v2.0.0 release, working within tight Claude Pro session limits.

**Session discipline:** one session = one phase. Each phase builds, passes
tests, and is shippable on its own. Start each session by pointing Claude at
this file ("continue V2-PLAN.md, phase N"). Jeff does manual verification
(computer-use can't see ad-hoc-signed apps); Claude verifies via unit tests
and inspecting saved PNGs/clipboard.

## Scope decisions (made 2026-07-02)

- ✅ Screen Draw mode (ZoomIt "Draw", Ctrl+2 there) — flagship
- ✅ Frozen Zoom mode (ZoomIt "Zoom", Ctrl+1 there), combinable with Draw
- ✅ Whiteboard / blackboard variants of Draw
- ✅ Break timer (ZoomIt Ctrl+3)
- ⚠️ LiveZoom — stretch only; macOS has no click-through magnification API
  for third parties. Built-in Accessibility Zoom (⌃+scroll) already covers it.
  Revisit only if frozen zoom feels insufficient in practice.
- ❌ Screen recording — PRD non-goal (video/GIF)
- ❌ DemoType — niche, needs Accessibility permission
- Snip — already the core app

No new permissions needed: Screen Recording grant covers everything above.

## Phase 1 — Screen Draw mode ✅ DONE (2026-07-02; Jeff verified SD1–SD11 all pass)

Hotkey (default ⌃⇧D, configurable like the others) captures the full screen
and shows it 1:1 in a borderless fullscreen window with annotation tools on
top. Reuses `EditorDocument`, `Annotation`, and `Renderer` (annotations are
already in image-pixel coordinates — the fullscreen window is just another
view of the same document).

Shipped as designed, in `Sources/ScreenDraw.swift` (controller + fullscreen
borderless window + SwiftUI tool strip) with small edits to EditorDocument
(`clearAnnotations()`), EditorWindow (accepts an existing document for the
⌘E handoff), CaptureCoordinator (`drawOnScreen()`), AppSettings/SettingsWindow/
AppDelegate (⌃⇧D hotkey, Settings row, menu item). Key handling is a pure
mapper (`ScreenDrawKeys.command`) — 13 new unit tests (94 total, all green).
Extras beyond plan: highlighter + select tools, 8-color ZoomIt-style swatch
palette, single-letter tool shortcuts (P/A/L/B/E/T/H/V), bottom hint bar,
save-cancel restores the session instead of losing drawings. Manual checklist
items SD1–SD11 added to TESTING.md — Jeff verifies before release.

## Phase 2 — Frozen Zoom mode + board modes (one session)

Hotkey (default ⌃⇧Z) freezes the screen into the same overlay window, starts
zoomed 1×, scroll wheel zooms toward the cursor (up to ~8×), mouse-move pans
(ZoomIt style), double-click or Esc exits.

- Zoom is a transform on the overlay's image view — capture code unchanged
- Entering draw (any tool key or ⌃⇧D while zoomed) freezes the current
  zoom/pan and lets you annotate the magnified view; copy/save exports what
  you see (viewport crop), matching ZoomIt behavior
- Whiteboard (W) / blackboard (K) inside Draw mode: swap the screenshot for
  solid white/black — trivial once Phase 1 exists
- Unit tests: zoom-toward-cursor math, pan clamping, viewport-crop geometry
  (pure functions, easy to test)

## Phase 3 — Break timer, polish, release v2.0.0 (one session)

- Break timer: menu-bar item + optional hotkey; fullscreen countdown
  (reuse/extend `CountdownHUD`), configurable minutes, Esc cancels,
  optional sound at zero
- Settings: new "Screen modes" section (hotkeys, default pen color/width,
  timer minutes)
- README + TESTING.md checklist updates for the three new modes
- Version bump in Packaging/Info.plist, `./build.sh`, Jeff runs the manual
  checklist, then tag + `gh release create` v2.0.0

## Phase 4 (optional, decide after living with v2 for a while)

- LiveZoom via SCStream: live screen restreamed zoomed into an overlay —
  view-only (clicks land on the overlay, not what's under it). Only worth it
  if frozen zoom + macOS built-in zoom leave a real gap.
- Cursor spotlight / dim-around-cursor for presentations (small, but was cut
  from the editor backlog as niche — reconsider only on demand).

## Notes

- BACKLOG.md items are unaffected; this plan is additive. The editor
  backlog's "pin screenshot" (#11) shares the borderless-overlay-window
  machinery with Phase 1 — cheap to do afterwards if wanted.
- Hotkey defaults must not collide with existing ⌃⇧3/4/5 or common app
  shortcuts; all configurable in Settings anyway.
