# Testing

## Automated tests

```bash
swift run NiceShotTests
```

110 unit tests cover the logic core — annotation geometry (bounds, hit-testing,
move, resize handles), editor undo/redo, crop math, the text-editing lifecycle,
hotkey encoding/display, screen draw and frozen zoom key handling, zoom
viewport math (zoom-toward-cursor, pan clamping, viewport crop), screen-coordinate
conversion, filename uniquing, PNG DPI metadata — plus rendering smoke tests that draw every annotation type
through the real export pipeline and verify pixels changed where they should
(blur obscures only its region, redaction is opaque black, effects alter edges,
and so on). They run automatically on every push via GitHub Actions
(`.github/workflows/tests.yml`).

Note: the tests are a small executable rather than a `swift test` bundle
because the Xcode Command Line Tools' test helper silently runs nothing;
see the comment in `Tests/TestMain.swift`. The rendering/export tests skip
themselves on CI because `ImageRenderer` needs a GUI session.

## Manual checklist (before a release)

Screen capture and the overlay UI can't run on headless CI, so walk these
before tagging a release. Each line should take a few seconds.

### Capture
1. ⌃⇧4 → drag a region → size badge updates while dragging; capture matches the selected area.
1b. ⌃⇧4 → move the mouse without clicking → magnifier loupe follows with a zoomed view, crosshair, and pixel coordinates; it flips sides near screen edges.
2. ⌃⇧4 → press Esc → overlay disappears, nothing captured, focus returns to the previous app.
3. ⌃⇧5 → hovering highlights windows with the app name; clicking captures only that window.
4. ⌃⇧3 → captures the display under the mouse (verify per-display on multi-monitor).
5. Menu bar → Timed Capture → 3 Seconds → countdown shows, HUD is *not* in the final image.

### Screen draw (v2)
SD1. ⌃⇧D → screen freezes in place with a floating tool strip at the top and a shortcut hint at the bottom; the pen is pre-selected and drawing works immediately.
SD2. Every strip tool works (select/pen/marker/arrow/line/box/ellipse/text); single letters switch tools (P pen, A arrow, B box, E ellipse, L line, T text, H marker, V select).
SD3. Color swatches change the drawing color (ring marks the active swatch); line-weight menu changes stroke width.
SD4. T → click → type text; while typing, letters do NOT switch tools; Esc ends typing (first press) and only a second Esc closes the mode.
SD5. ⌘Z / ⇧⌘Z undo/redo; trash button clears all drawings and one ⌘Z brings them all back; ⌫ deletes the selected annotation.
SD6. ⌘C → mode closes, shutter sound plays, pasting into Preview shows the screen with drawings baked in.
SD7. ⌘S → mode hides, save dialog appears; cancel brings the mode back with drawings intact; confirming saves and closes.
SD8. ⌘E → full editor opens with the frozen screen and all drawings editable (move/resize them).
SD9. Esc → closes without saving; focus returns to the previous app; no stray windows remain.
SD10. Multi-monitor: mode opens on the display under the mouse.
SD11. Menu bar → "Draw on Screen" starts the mode; Settings → "Draw on Screen" hotkey can be rebound and the new combo works.
SD12. W → screenshot swaps to a solid whiteboard (drawings stay); W again brings the screenshot back; K does the same with a blackboard; ⌘Z undoes a board swap. The two small white/black buttons in the strip do the same.

### Frozen zoom (v2)
ZM1. ⌃⇧Z → screen freezes at 1× with a hint bar at the bottom; nothing looks different otherwise (it's showing the frozen screen 1:1).
ZM2. Scroll up → zooms in toward the mouse cursor (the point under the cursor stays put); scroll down zooms back out; zoom stops at 8× and at 1×; the hint shows the current zoom factor. ↑/↓ arrows also zoom.
ZM3. While zoomed, moving the mouse pans — far left/right/top/bottom of the screen shows the matching edge of the image.
ZM4. Esc or double-click → exits; focus returns to the previous app.
ZM5. While zoomed, ⌘C → closes and pasting into Preview shows exactly the magnified view that was on screen (not the full screen).
ZM6. While zoomed, ⌘S → save dialog; the saved PNG is the zoomed viewport. Cancel brings zoom mode back.
ZM7. While zoomed, press P (or any tool letter, or ⌃⇧D) → the view stays exactly as it was (still magnified) and the draw tool strip appears; drawing, W/K boards, undo, and ⌘C/⌘S all work on the magnified view; ⌘C exports what you see.
ZM8. At 1× (no zoom), pressing P enters draw mode with the full screen — same as ⌃⇧D.
ZM9. While zoomed, ⌘E → the full editor opens with just the viewport crop.
ZM10. Menu bar → "Zoom Screen" starts the mode; Settings → "Zoom Screen" hotkey can be rebound and the new combo works.
ZM11. Multi-monitor: mode opens on the display under the mouse; scroll/pan stay on that display.

### Post-capture panel
6. Panel appears bottom-right without stealing keyboard focus.
7. Save → cancel the dialog → panel stays; Save → confirm → file lands with correct name.
8. Copy → paste into Preview (⌘N) shows the capture.
9. Two captures in a row → panels stack without covering each other.
9b. Share button opens the share sheet; sharing to Mail/Messages attaches the PNG.
9c. With "Copy new captures to the clipboard" on → a green "Copied" badge shows and pasting works without pressing Copy.
9d. Shutter sound plays on capture; disabling the setting silences it.

### Editor
10. Every tool draws; arrows/shapes can be selected, moved, and resized by handles.
10b. Tool ribbon shows icon + name per tool; the chevron collapses it to compact icons and the choice survives reopening the editor.
11. Double-click a text/callout → edit; empty text annotation disappears; empty callout stays.
12. ⌘Z/⇧⌘Z walk history correctly across draw, move, crop, and delete.
13. Crop → Return applies, Esc cancels; annotations stay glued to image content.
14. Effects (border/shadow/corners) preview live and appear in the saved PNG.
15. Exported PNG at 2× displays at the correct size when pasted/opened.

### Settings
16. Record a custom shortcut → menu bar shows it; old combo stops working, new one works.
17. While recording, pressing an existing capture shortcut does *not* trigger a capture.
18. Quick-save mode writes uniquely-named files to the chosen folder.
18b. Format set to JPEG → saves write .jpg files that open in Preview; quality slider appears; PNG remains the default.
18c. "After each capture" set to Copy / Save / Open the editor → capture skips the panel and does that action; back on "Show the capture panel" the panel returns.
19. Launch at login toggles without error when the app is in /Applications.
20. Settings window opens showing every section and can be resized.
