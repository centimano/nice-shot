#!/bin/bash
# Build and package Nice Shot.app into dist/.
#
#   ./build.sh          release build: dist/Nice Shot.app
#   ./build.sh --beta   beta build:    dist/Nice Shot Beta.app
#
# The beta variant gets its own bundle identifier (com.jeff.nice-shot.beta)
# and name, so macOS treats it as a separate app: it can be installed next to
# the release version and gets its own Screen Recording grant. TCC ties
# permissions to bundle id + code signature, and ad-hoc signatures change on
# every rebuild — reusing the release identity for test builds confuses the
# permission system. Note: don't run both apps at once; the second one loses
# the global-hotkey registrations.
set -euo pipefail
cd "$(dirname "$0")"

BETA=0
if [ "${1:-}" = "--beta" ]; then
  BETA=1
fi

if [ ! -f Packaging/AppIcon.icns ]; then
  echo "Generating app icon…"
  swift Scripts/makeicon.swift
fi

# Build only the app product: the test executable uses @testable, which is
# debug-only, so it must not be part of release builds.
swift build -c release --product NiceShotApp

APP_NAME="Nice Shot"
if [ $BETA -eq 1 ]; then
  APP_NAME="Nice Shot Beta"
fi
APP="dist/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NiceShotApp "$APP/Contents/MacOS/NiceShot"
cp Packaging/Info.plist "$APP/Contents/"
if [ -f Packaging/AppIcon.icns ]; then
  cp Packaging/AppIcon.icns "$APP/Contents/Resources/"
fi

if [ $BETA -eq 1 ]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
  /usr/libexec/PlistBuddy \
    -c "Set :CFBundleIdentifier com.jeff.nice-shot.beta" \
    -c "Set :CFBundleName $APP_NAME" \
    -c "Set :CFBundleDisplayName $APP_NAME" \
    -c "Set :CFBundleShortVersionString $VERSION beta" \
    "$APP/Contents/Info.plist"
fi

# Ad-hoc sign so the Screen Recording permission sticks across rebuilds.
codesign --force -s - "$APP"

echo "Built: $APP"
