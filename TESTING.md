# Testing

## Automated tests

```bash
swift run NiceShotTests
```

72 unit tests cover the logic core — annotation geometry (bounds, hit-testing,
move, resize handles), editor undo/redo, crop math, the text-editing lifecycle,
hotkey encoding/display, screen-coordinate conversion, filename uniquing, PNG
DPI metadata — plus rendering smoke tests that draw every annotation type
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

### Post-capture panel
6. Panel appears bottom-right without stealing keyboard focus.
7. Save → cancel the dialog → panel stays; Save → confirm → file lands with correct name.
8. Copy → paste into Preview (⌘N) shows the capture.
9. Two captures in a row → panels stack without covering each other.

### Editor
10. Every tool draws; arrows/shapes can be selected, moved, and resized by handles.
11. Double-click a text/callout → edit; empty text annotation disappears; empty callout stays.
12. ⌘Z/⇧⌘Z walk history correctly across draw, move, crop, and delete.
13. Crop → Return applies, Esc cancels; annotations stay glued to image content.
14. Effects (border/shadow/corners) preview live and appear in the saved PNG.
15. Exported PNG at 2× displays at the correct size when pasted/opened.

### Settings
16. Record a custom shortcut → menu bar shows it; old combo stops working, new one works.
17. While recording, pressing an existing capture shortcut does *not* trigger a capture.
18. Quick-save mode writes uniquely-named files to the chosen folder.
19. Launch at login toggles without error when the app is in /Applications.
