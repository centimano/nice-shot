# Nice Shot — notes for Claude

macOS menu-bar screenshot app (SnagIt-style). Swift + SwiftUI + ScreenCaptureKit, built with SwiftPM only — **no Xcode on this machine, Command Line Tools only, keep it that way** (so friends can build with just CLT).

## Build & test rules
- **Test builds for Jeff: ALWAYS `./build.sh --beta`** → `dist/Nice Shot Beta.app` (bundle id `com.jeff.nice-shot.beta`), until v2.0.0 ships. Plain `./build.sh` is for the actual release step only — a test build with the release bundle id fights the installed app's Screen Recording permission.
- Bump `CFBundleVersion` in `Packaging/Info.plist` for every new beta handed to Jeff.
- Tests: `swift run NiceShotTests` (Swift Testing, run as an *executable* — `swift test` silently runs zero tests under CLT). `build.sh` must build `--product NiceShotApp`.
- Never run the release and beta apps at the same time (the second app's global hotkeys fail silently).
- Release flow: bump both version keys in Info.plist → `./build.sh` → `ditto -c -k --keepParent` → `gh release create`. Ad-hoc signed, not notarized.

## Gotchas
- After renaming/moving the repo folder: `rm -rf .build` (stale module cache).
- Every `open dist/….app` registers that copy with Launch Services → ghost duplicates in the macOS Apps list. Cleanup: `lsregister -u <path>` per stale entry.
- Claude's computer-use tools **cannot see or control this app** (ad-hoc signed apps are excluded). Manual checklists in TESTING.md are done by Jeff; Claude verifies by inspecting saved PNGs/clipboard afterward.
- Rendering/export tests skip on CI (ImageRenderer needs a GUI).

## Docs
`PRD.md` spec · `V2-PLAN.md` current phased work · `TESTING.md` manual checklists · `BACKLOG.md` triaged ideas. To resume v2 work: "continue V2-PLAN.md, phase N".
