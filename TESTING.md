# Testing

## Automated tests

```bash
swift run NiceShotTests
```

The unit tests cover the logic core — annotation geometry (bounds, hit-testing,
move, resize handles), editor undo/redo, crop math, the text-editing lifecycle,
hotkey encoding/display and duplicate detection, unsaved-changes tracking, screen draw and frozen zoom key handling, zoom
viewport math (zoom-toward-cursor, pan clamping, viewport crop), screen-coordinate
conversion, filename uniquing, PNG DPI metadata, capture-tray routing, contents
and layout, thumbnail sizing, loupe repaint areas, no-overwrite saving, and
private share-file staging and cleanup — plus rendering smoke tests that draw every annotation type
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
1. ⇧⌘S → drag a region → size badge updates while dragging; capture matches the selected area.
1b. ⇧⌘S → move the mouse without clicking → magnifier loupe follows with a zoomed view, crosshair, and pixel coordinates; it flips sides near screen edges.
2. ⇧⌘S → press Esc → overlay disappears, nothing captured, focus returns to the previous app.
3. ⇧⌘W → hovering highlights windows with the app name; clicking captures only that window.
4. ⇧⌘F → captures the display under the mouse (verify per-display on multi-monitor).
5. Menu bar → Timed Capture → 3 Seconds → countdown shows, HUD is *not* in the final image.

### Screen draw (v2)
SD1. ⇧⌘D → screen freezes in place with a floating tool strip at the top and a shortcut hint at the bottom; the pen is pre-selected and drawing works immediately.
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
ZM1. ⇧⌘Z → screen freezes at 1× with a hint bar at the bottom; nothing looks different otherwise (it's showing the frozen screen 1:1).
ZM2. Scroll up → zooms in toward the mouse cursor (the point under the cursor stays put); scroll down zooms back out; zoom stops at 8× and at 1×; the hint shows the current zoom factor. ↑/↓ arrows also zoom.
ZM3. While zoomed, moving the mouse pans — far left/right/top/bottom of the screen shows the matching edge of the image.
ZM4. Esc or double-click → exits; focus returns to the previous app.
ZM5. While zoomed, ⌘C → closes and pasting into Preview shows exactly the magnified view that was on screen (not the full screen).
ZM6. While zoomed, ⌘S → save dialog; the saved PNG is the zoomed viewport. Cancel brings zoom mode back.
ZM7. While zoomed, press P (or any tool letter, or ⇧⌘D) → the view stays exactly as it was (still magnified) and the draw tool strip appears; drawing, W/K boards, undo, and ⌘C/⌘S all work on the magnified view; ⌘C exports what you see.
ZM8. At 1× (no zoom), pressing P enters draw mode with the full screen — same as ⇧⌘D.
ZM9. While zoomed, ⌘E → the full editor opens with just the viewport crop.
ZM10. Menu bar → "Zoom Screen" starts the mode; Settings → "Zoom Screen" hotkey can be rebound and the new combo works.
ZM11. Multi-monitor: mode opens on the display under the mouse; scroll/pan stay on that display.

### Post-capture panel
6. Panel appears bottom-right without stealing keyboard focus.
7. Save → cancel the dialog → panel stays; Save → confirm → file lands with correct name.
8. Copy → paste into Preview (⌘N) shows the capture.
9. Two captures in a row → a single capture tray replaces the panel (see "Capture tray" below).
9b. Share button opens the share sheet; sharing to Mail/Messages attaches the PNG.
9c. With "Copy new captures to the clipboard" on → a green "Copied" badge shows and pasting works without pressing Copy.
9d. Shutter sound plays on capture; disabling the setting silences it.

### Capture tray (2.2)
Set Settings → "After each capture" to "Show the capture panel".
T1. One capture → the classic panel appears exactly as before (big thumbnail, Edit/Save/Copy/Share). Dismiss it.
T2. Two captures in a row (leave the first panel up) → the panel is replaced, in the same corner, by one tray titled "2 Captures" with the newest on top. Nothing stacks.
T3. Keep capturing → each new shot joins the top of the tray; after 4 the list scrolls (half a row peeks out at the bottom) and the tray stops growing.
T4. Row buttons: ✎ opens that capture in the editor and removes it from the tray; ↓ saves it (cancel the dialog → it stays); Copy copies it (paste to check) and removes it; Share opens the share sheet; ⓧ discards it.
T5. Handle captures until one is left → it stays in the tray; handle the last → the tray disappears. The next single capture gets the classic panel again (T1).
T6. Save All with "Ask where to save" ON → one folder picker → every capture saved there with unique names (… 2.png, … 3.png), in the order taken; the tray closes. Cancel the picker → nothing changes.
T7. Save All with "Ask where to save" OFF → all captures land in the quick-save folder without any dialog.
T8. Discard All (trash) → "Discard all N captures?" → Cancel keeps them; Discard clears the tray. Focus returns to the app you were using.
T9. Chevron ⌄ folds the tray to a small "N Captures" stack with fanned thumbnails; clicking it reopens. Quit and relaunch → the tray opens folded/unfolded the way you left it.
T10. With "Copy new captures to the clipboard" ON → only the newest row shows the green ✓.
T11. The tray never steals keyboard focus and never appears in a later screenshot (capture full screen with the tray showing).
T12. With "After each capture" set to Copy, Save, or Open the editor → no panel and no tray, same as before.
T13. Classic panel up → click Save… → while the dialog is open press ⇧⌘F (skip this step if macOS doesn't take the shortcut while the dialog is open) → finish the save → the tray shows only the newer capture.

### Security & resources (2.2)
S1. Share a capture via the share sheet → in Finder, Go → Go to Folder → `$TMPDIR/NiceShot-Share` shows a folder holding it; quit and relaunch Nice Shot → that folder is empty.
S2. Quick-save mode → take several captures within one second → all are saved, none overwritten.
S3. Activity Monitor → Nice Shot idle in the menu bar uses ~0% CPU and no energy impact; after clearing a tray of 10 captures its memory drops back down within a few seconds.
S4. Region select (⇧⌘S) on a multi-monitor setup → move the pointer from one display to the other → the loupe follows and doesn't stay behind on the first display.

### Editor
10. Every tool draws; arrows/shapes can be selected, moved, and resized by handles.
10b. Tool ribbon shows icon + name per tool; the chevron collapses it to compact icons and the choice survives reopening the editor.
11. Double-click a text/callout → edit; empty text annotation disappears; empty callout stays.
12. ⌘Z/⇧⌘Z walk history correctly across draw, move, crop, and delete.
13. Crop → Return applies, Esc cancels; annotations stay glued to image content.
14. Effects (border/shadow/corners) preview live and appear in the saved PNG.
15. Exported PNG at 2× displays at the correct size when pasted/opened.

### Fable polish pass (September 2026)
Before starting: quit the installed Nice Shot, run `./build.sh --beta`, open `dist/Nice Shot Beta.app`. Its icon appears in the menu bar and its hotkeys are the defaults above (⇧⌘S/W/F/D/Z) unless you rebound them in the beta's own Settings.
F1. Capture (any kind) → leave the panel showing → ⇧⌘F → the new full-screen capture does NOT contain the first capture's panel.
F2. Editor → Callout → drag a bubble → while typing, the colored bubble stays visible under the text field; finish → text sits inside the bubble.
F3. Editor → draw anything → ⌘W → "Save / Cancel / Don't Save" sheet; Cancel keeps the window; Don't Save closes; Save… opens the dialog and closes on confirm. The title bar shows the edited dot while there is unsaved work; Copy or Save clears it and ⌘W then closes silently. Undo everything back to empty → ⌘W closes silently.
F4. Editor with unsaved annotations → ⌘Q from the menu bar → "Quit Nice Shot?" confirmation; Cancel keeps running.
F5. Settings → record ⇧⌘W for Capture Region → red "Already used by Capture Window" text, recording continues; press another combo → accepted.
F6. Menu bar → Capture Region / Draw on Screen / Zoom Screen → the frozen screen does not contain a fading status menu.
F7. ⇧⌘W → click a window of the app you were just using → its title bar looks active (not dimmed) in the capture.
F8. ⇧⌘S → drag past the right/bottom screen edge → size badge stops growing at the edge; releasing off-screen still captures up to the edge (no error).
F9. (Superseded in 2.2 by the capture tray: captures never stack as separate panels.)
F10. Editor → Pen → draw a big loose loop around a Box → Select tool → clicking the box inside the loop selects the box, not the pen stroke; clicking the ink selects the pen.
F11. Editor → Text → type a few words → ⌘Z while still typing → only the last typed text is undone, the text box stays.
F12. Two editors open → the second is offset down-right from the first, not exactly on top.
F13. Editor → double-click existing text → change nothing → click away → ⌘Z undoes the *previous* action (no empty undo step).

### Settings
16. Record a custom shortcut → menu bar shows it; old combo stops working, new one works.
17. While recording, pressing an existing capture shortcut does *not* trigger a capture.
18. Quick-save mode writes uniquely-named files to the chosen folder.
18b. Format set to JPEG → saves write .jpg files that open in Preview; quality slider appears; PNG remains the default.
18c. "After each capture" set to Copy / Save / Open the editor → capture skips the panel and does that action; back on "Show the capture panel" the panel returns.
19. Launch at login toggles without error when the app is in /Applications.
20. Settings window opens showing every section and can be resized.
