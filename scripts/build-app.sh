#!/bin/bash
# Builds "STIX Island.app" and a zip in ./dist. Runs on macOS (CI or local).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="STIX Island"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

rm -rf dist
APP="dist/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/STIXIsland" "$APP/Contents/MacOS/STIXIsland"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Info.plist > "$APP/Contents/Info.plist"
cp Resources/mediaremote-adapter.pl "$APP/Contents/Resources/"
ditto Resources/MediaRemoteAdapter.framework "$APP/Contents/Resources/MediaRemoteAdapter.framework"

# App icon from a 1024px PNG.
if [ -f Resources/AppIcon.png ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature (replace "-" with a Developer ID identity for release builds).
SIGN_ID="${SIGN_ID:--}"
codesign --force --sign "$SIGN_ID" "$APP/Contents/Resources/MediaRemoteAdapter.framework"
codesign --force --sign "$SIGN_ID" "$APP"

ditto -c -k --keepParent "$APP" "dist/STIX-Island-$VERSION.zip"
echo "Built dist/STIX-Island-$VERSION.zip"
