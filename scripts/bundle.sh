#!/usr/bin/env bash
#
# Build ClaudeUsageBar and wrap the release binary into a menu-bar .app bundle.
# Must be run on macOS (needs the Swift toolchain + codesign).
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ClaudeUsageBar"
DISPLAY_APP="ClaudeUsageBar.app"
BUILD_DIR=".build/release"
OUT_DIR="dist"
APP_BUNDLE="$OUT_DIR/$DISPLAY_APP"

echo "==> swift build -c release"
swift build -c release

if [[ ! -f "$BUILD_DIR/$APP_NAME" ]]; then
    echo "error: expected binary at $BUILD_DIR/$APP_NAME not found" >&2
    exit 1
fi

echo "==> assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "==> ad-hoc code signing"
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Built: $APP_BUNDLE"
echo "Run it:        open \"$APP_BUNDLE\""
echo "Install it:    drag $DISPLAY_APP into /Applications"
