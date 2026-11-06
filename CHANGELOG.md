# Changelog

Release notes for each version. The Release workflow publishes the section
matching the version in `Packaging/Info.plist`. Older releases are described
on the [releases page](https://github.com/centimano/nice-shot/releases).

## 2.2.0

**New: the capture tray.** Take several screenshots back-to-back and they
no longer pile up as a stack of floating panels. The first capture still gets
the familiar panel. Take another while it's showing and both move into one
tray in the same corner, with each capture as a row: Edit, Save, Copy, Share,
or Discard. **Save All** saves the lot in one go (one folder pick instead of a
dialog per image), and **Discard All** clears the tray after asking. Click the
chevron to fold the tray into a small "N Captures" stack; it remembers whether
you left it open or folded. The tray only appears when "After each capture" is
set to show the panel. The copy, save, and editor modes behave as before.

**Security**
- The app is now signed with Apple's hardened runtime, which blocks code
  injection and library tampering.
- Images handed to the share sheet are kept in a private folder and cleaned
  up automatically. They used to be left in the temporary folder for good.
- Quick-save can never overwrite an existing file, even one that appears at
  the same instant. Saves through the dialog are written atomically, so a
  failed save can't leave a half-written file.
- Errors go to the system log (Console.app) with private details redacted.
- Build automation hardened: least-privilege tokens and pinned dependencies.

**Performance**
- Capture panels hold a small preview instead of the full-resolution image
  (on a 5K display, about 0.5 MB instead of 60 MB per panel).
- Full-screen overlays (region select, window picker, draw, zoom) release
  their memory as soon as they close.
- Region select and the window picker redraw only what changes as the mouse
  moves, instead of repainting the whole screen each frame.
- The magnifier loupe no longer lingers on a display the pointer has left.

**Install**
Unzip, drag `Nice Shot.app` to Applications, and replace the old one. The app
is ad-hoc signed: right-click → Open the first time, and re-grant Screen
Recording if macOS asks.
