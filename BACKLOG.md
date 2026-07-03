# Nice Shot — Feature Backlog

Sourced from the original "Super Duper Screenshot" Product Spec v0.2 (June 2026),
diffed against what shipped through v1.3.0, merged with the PRD's former
"Future ideas" list. Ordered by effort-to-value: Tier 1 items are small,
self-contained wins; Tier 3 items are real projects.

Spec requirement IDs (CAP-/OVR-/EDT-/RED-/BEA-/EXP-) refer to the spec PDF.

## Tier 1 — Low-hanging fruit (small, contained, each fits a short session)

5. **Keyboard nudging of selected annotations** *(spec v0.2 "keyboard nudging")*
   Arrow keys move the selection 1 px, Shift+arrows 10 px. Selection and
   pixel-coordinate model already exist.

6. **Warn on duplicate hotkeys** *(found in v2 quality pass, July 2026)*
   Recording a shortcut already used by another action silently breaks the
   second one (RegisterEventHotKey fails with only a console log). The
   recorder should refuse or warn. Needs a small design decision: block,
   swap, or warn-and-allow.

## Tier 2 — Medium (worth doing, needs a design pass or a full session)

9. **Filename templates** *(EXP-003, P1)*
   Quick-save filenames from a template: `{date}`, `{time}`, `{captureType}`,
   `{appName}`, `{windowTitle}`, `{seq}`. App name/window title only apply to
   window captures.

11. **Pin screenshot as floating reference** *(v0.4)*
    "Pin" button puts the capture in a borderless always-on-top window;
    drag to move, double-click or Esc to close.

12. **Color picker tool** *(v0.4)*
    Eyedropper in the editor (or capture overlay) that copies the hex value.
    The region loupe already magnifies pixels — shared machinery.

## Tier 3 — Large (multi-session projects)

15. **Scrolling capture** *(CAP-007, P3 / spec v0.5)*
    Accessibility-assisted scroll-and-stitch; browsers and standard scroll views
    first; fail gracefully elsewhere. Needs the Accessibility permission.

16. **Annotation style presets** *(spec v0.2; was in PRD future ideas)*
    Save/recall combinations of color, weight, and font size.

## Carried over from PRD future ideas (not in spec)

- Multi-display region drag
- Sparse-color border themes

## Spec items intentionally NOT adopted

- **Reveal in Finder / copy file path** *(v0.4)* — cut in triage (June 2026).
- **Capture previous region** *(CAP-005)* — cut in triage.
- **True blur redaction** *(RED-001)* — cut in triage; pixelate + solid black
  already cover redaction, and blur is the weakest mode anyway.
- **Beautify padding/background + presets** *(BEA-001/BEA-002)* — cut in triage;
  border/shadow/rounded corners are enough polish for this app.
- **Drag-and-drop from the post-capture panel** *(OVR-001 "later")* — cut in triage.
- **Window capture shadow option** *(CAP-003)* — cut in triage.
- **Recent captures shelf** *(OVR-003)* — cut in triage.
- **Pixel ruler** *(v0.4)* — the region loupe already shows live size + pixel
  coordinates; a separate ruler tool duplicates it. Revisit only on demand.
- **Spotlight tool** *(EDT-001 "later")* — niche; highlighter + crop cover it.
- **WebP export** — no native macOS encoder; not worth a third-party dependency
  in a zero-dependency app.
- **Export size preview** *(v0.3)* — folds into #7/#8 if we do beautify.
- Everything in the spec's non-goals (cloud, OCR, video/GIF, plugins, AI,
  project files) — Nice Shot's PRD already agrees.

## Already shipped (spec → Nice Shot, for the record)

Shipped in June 2026 triage session: **JPEG export** *(EXP-002 — format picker
in Settings + save dialog, quality slider, PNG still default)* and
**configurable default post-capture action** *(OVR-002 — panel / copy / save /
open editor)*.


The spec's full MVP (v0.1) and v0.2 scope, plus: delayed capture (CAP-006 → timed
3/5/10 s), magnifier (v0.4 → region loupe), undo/redo, crop, ellipse / highlighter /
pen / step markers (spec "later tools"), callouts and share sheet (beyond spec),
border + shadow + rounded corners (part of BEA-001), auto-copy to clipboard,
flattened irreversible exports (RED-002/EDT-004), launch at login, shutter sound.
