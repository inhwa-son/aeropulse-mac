#!/usr/bin/env bash
set -euo pipefail

# AeroPulse DMG Packager
# Usage: ./scripts/create-dmg.sh [app_path] [output_dir]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/out/release/AeroPulse.app}"
OUTPUT_DIR="${2:-$ROOT_DIR/out/release}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: App bundle not found at $APP_PATH" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")
DMG_NAME="AeroPulse-${VERSION}-${BUILD}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
TEMP_DIR=$(mktemp -d)
VOLUME_NAME="AeroPulse ${VERSION}"

echo "==> Creating DMG: $DMG_NAME"
echo "    App: $APP_PATH"
echo "    Version: $VERSION (build $BUILD)"

# Prepare DMG contents
mkdir -p "$TEMP_DIR/dmg"
cp -R "$APP_PATH" "$TEMP_DIR/dmg/"
ln -s /Applications "$TEMP_DIR/dmg/Applications"

# Create DMG
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$TEMP_DIR/dmg" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

rm -rf "$TEMP_DIR"

echo "==> DMG created: $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"
