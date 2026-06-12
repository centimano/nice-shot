#!/bin/bash
# Build and package Nice Shot.app into dist/.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f Packaging/AppIcon.icns ]; then
  echo "Generating app icon…"
  swift Scripts/makeicon.swift
fi

# Build only the app product: the test executable uses @testable, which is
# debug-only, so it must not be part of release builds.
swift build -c release --product NiceShotApp

APP="dist/Nice Shot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NiceShotApp "$APP/Contents/MacOS/NiceShot"
cp Packaging/Info.plist "$APP/Contents/"
if [ -f Packaging/AppIcon.icns ]; then
  cp Packaging/AppIcon.icns "$APP/Contents/Resources/"
fi

# Ad-hoc sign so the Screen Recording permission sticks across rebuilds.
codesign --force -s - "$APP"

echo "Built: $APP"
