#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Swifotine"
VERSION="${1:-1.0}"

SWIFTPM_DIR="$ROOT_DIR/SwifotineMac"
RELEASE_BINARY="$SWIFTPM_DIR/.build/arm64-apple-macosx/release/$APP_NAME"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_STAGE_DIR="$DIST_DIR/dmg-root"
DMG_PATH="$ROOT_DIR/${APP_NAME}_v${VERSION}.dmg"
ICON_PATH="$ROOT_DIR/assets/AppIcon.icns"

if [[ ! -f "$ICON_PATH" ]]; then
  "$ROOT_DIR/scripts/generate_app_icon.sh"
fi

pushd "$SWIFTPM_DIR" >/dev/null
swift build -c release
popd >/dev/null

if [[ ! -x "$RELEASE_BINARY" ]]; then
  echo "Release binary not found: $RELEASE_BINARY" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE" "$DMG_STAGE_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/backend/slsk-helper"
mkdir -p "$APP_BUNDLE/Contents/Resources/vendor"

cp "$RELEASE_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cp "$ROOT_DIR/backend/slsk-helper/swifotine_helper.py" "$APP_BUNDLE/Contents/Resources/backend/slsk-helper/swifotine_helper.py"
cp -R "$ROOT_DIR/vendor/nicotine-plus" "$APP_BUNDLE/Contents/Resources/vendor/nicotine-plus"
cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.swifotine.desktop</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

mkdir -p "$DMG_STAGE_DIR"
cp -R "$APP_BUNDLE" "$DMG_STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$DMG_STAGE_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "Built app bundle: $APP_BUNDLE"
echo "Built DMG: $DMG_PATH"
