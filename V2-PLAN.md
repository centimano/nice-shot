# Nice Shot v2 — ZoomIt-inspired live screen modes

Planned 2026-07-02. Goal: bring the useful parts of Sysinternals ZoomIt to
Nice Shot as a v2.0.0 release, working within tight Claude Pro session limits.

**Session discipline:** one session = one phase. Each phase builds, passes
tests, and is shippable on its own. Start each session by pointing Claude at
this file ("continue V2-PLAN.md, phase N"). Jeff does manual verification
(computer-use can't see ad-hoc-signed apps); Claude verifies via unit tests
and inspecting saved PNGs/clipboard.

**Build discipline:** until v2.0.0 ships, every build handed to Jeff is
`./build.sh --beta` → `dist/Nice Shot Beta.app` (own bundle id, own Screen
Recording grant — plain `./build.sh` fights the installed v1.4.0 and is
reserved for the phase-3 release step). Bump CFBundleVersion in
Packaging/Info.plist each time so About shows which beta is running.

## Scope decisions (made 2026-07-02)

- ✅ Screen Draw mode (ZoomIt "Draw", Ctrl+2 there) — flagship
- ✅ Frozen Zoom mode (ZoomIt "Zoom", Ctrl+1 there), combinable with Draw
- ✅ Whiteboard / blackboard variants of Draw
- ❌ Break timer (ZoomIt Ctrl+3) — dropped 2026-07-02, Jeff's call: unnecessary
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

## Phase 2 — Frozen Zoom mode + board modes ✅ DONE (2026-07-02; Jeff verified ZM1–ZM11 + SD12 on beta 8)

Shipped as designed: `Sources/ScreenZoom.swift` holds pure `ZoomMath`
(fraction-mapped pan means the point under the cursor stays fixed while
zooming — one function gives both behaviors), a pure `ScreenZoomKeys` mapper,
and `ScreenZoomController` with an AppKit zoom surface (scroll/arrow zoom to
8×, mouse-move pan, double-click/Esc exit, ⌘C/⌘S/⌘E export the viewport,
live zoom factor in the hint bar). Any tool key (or ⌃⇧D) hands a
viewport-cropped Capture to the Phase 1 ScreenDrawController, which gained
`initialTool` + a computed fitScale so crops display magnified; annotations
land on the crop so exports are exactly what's on screen. W/K whiteboard/
blackboard toggles in draw mode via undoable `EditorDocument.replaceBaseImage`
(+ two strip buttons). ⌃⇧Z hotkey wired through AppSettings/Settings/menu.
16 new unit tests (110 total, all green): zoom-toward-cursor invariance, pan
clamping, viewport-crop geometry, zoom keys, board keys, base-image undo.
Manual checklist ZM1–ZM11 and SD12 added to TESTING.md.

## Phase 3 — Release v2.0.0

v2 feature work is complete (2026-07-02): break timer dropped as unnecessary,
manual checklists verified on beta 8, README updated for the new modes.
Remaining, whenever Jeff wants to publish: bump both version keys in
Packaging/Info.plist → `./build.sh` (plain, release bundle id) → tag +
`gh release create` v2.0.0.

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
