#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Swifotine"
VERSION="${1:-1.0}"

SWIFTPM_DIR="$ROOT_DIR/SwifotineMac"
ARM_BINARY="$SWIFTPM_DIR/.build/arm64-apple-macosx/release/$APP_NAME"
X86_BINARY="$SWIFTPM_DIR/.build/x86_64-apple-macosx/release/$APP_NAME"

DIST_DIR="$ROOT_DIR/dist"
UNIVERSAL_BINARY="$DIST_DIR/$APP_NAME-universal"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_STAGE_DIR="$DIST_DIR/dmg-root"
DMG_PATH="$ROOT_DIR/${APP_NAME}_v${VERSION}.dmg"
ICON_PATH="$ROOT_DIR/assets/AppIcon.icns"

SIGN_IDENTITY="${SWIFOTINE_SIGN_IDENTITY:--}"
ALLOW_SINGLE_ARCH="${SWIFOTINE_ALLOW_SINGLE_ARCH:-0}"
NOTARIZE="${SWIFOTINE_NOTARIZE:-0}"
NOTARY_PROFILE="${SWIFOTINE_NOTARY_PROFILE:-}"
NOTARY_APPLE_ID="${SWIFOTINE_NOTARY_APPLE_ID:-}"
NOTARY_TEAM_ID="${SWIFOTINE_NOTARY_TEAM_ID:-}"
NOTARY_APP_PASSWORD="${SWIFOTINE_NOTARY_APP_PASSWORD:-}"

if [[ ! -f "$ICON_PATH" ]]; then
  "$ROOT_DIR/scripts/generate_app_icon.sh"
fi

build_arch() {
  local arch="$1"
  pushd "$SWIFTPM_DIR" >/dev/null
  swift build -c release --arch "$arch"
  popd >/dev/null
}

sign_path() {
  local path="$1"
  local deep_flag="${2:-0}"

  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    if [[ "$deep_flag" == "1" ]]; then
      codesign --force --deep --sign - "$path"
    else
      codesign --force --sign - "$path"
    fi
  else
    if [[ "$deep_flag" == "1" ]]; then
      codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$path"
    else
      codesign --force --timestamp --sign "$SIGN_IDENTITY" "$path"
    fi
  fi
}

notarize_dmg_if_requested() {
  if [[ "$NOTARIZE" != "1" ]]; then
    return
  fi

  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "Notarization requires Developer ID signing. Set SWIFOTINE_SIGN_IDENTITY." >&2
    exit 1
  fi

  if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [[ -n "$NOTARY_APPLE_ID" && -n "$NOTARY_TEAM_ID" && -n "$NOTARY_APP_PASSWORD" ]]; then
    xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$NOTARY_APPLE_ID" \
      --team-id "$NOTARY_TEAM_ID" \
      --password "$NOTARY_APP_PASSWORD" \
      --wait
  else
    cat >&2 <<EOF
Notarization requested but credentials were not provided.
Set one of:
  1) SWIFOTINE_NOTARY_PROFILE (preferred keychain profile)
  2) SWIFOTINE_NOTARY_APPLE_ID + SWIFOTINE_NOTARY_TEAM_ID + SWIFOTINE_NOTARY_APP_PASSWORD
EOF
    exit 1
  fi

  xcrun stapler staple "$DMG_PATH"
}

mkdir -p "$DIST_DIR"

echo "Building release binaries (arm64 + x86_64)..."
build_arch "arm64"
if ! build_arch "x86_64"; then
  if [[ "$ALLOW_SINGLE_ARCH" == "1" ]]; then
    echo "Warning: x86_64 build failed. Continuing with arm64-only artifact." >&2
  else
    echo "x86_64 build failed. Set SWIFOTINE_ALLOW_SINGLE_ARCH=1 to allow arm64-only packaging." >&2
    exit 1
  fi
fi

if [[ -x "$ARM_BINARY" && -x "$X86_BINARY" ]]; then
  lipo -create "$ARM_BINARY" "$X86_BINARY" -output "$UNIVERSAL_BINARY"
elif [[ -x "$ARM_BINARY" ]]; then
  cp "$ARM_BINARY" "$UNIVERSAL_BINARY"
else
  echo "Release binary not found for arm64: $ARM_BINARY" >&2
  exit 1
fi
chmod +x "$UNIVERSAL_BINARY"

rm -rf "$APP_BUNDLE" "$DMG_STAGE_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/backend/slsk-helper"
mkdir -p "$APP_BUNDLE/Contents/Resources/vendor"

cp "$UNIVERSAL_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cp "$ROOT_DIR/backend/slsk-helper/swifotine_helper.py" "$APP_BUNDLE/Contents/Resources/backend/slsk-helper/swifotine_helper.py"
chmod +x "$APP_BUNDLE/Contents/Resources/backend/slsk-helper/swifotine_helper.py"
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

echo "Signing app bundle with identity: $SIGN_IDENTITY"
sign_path "$APP_BUNDLE" 1
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

mkdir -p "$DMG_STAGE_DIR"
cp -R "$APP_BUNDLE" "$DMG_STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$DMG_STAGE_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  sign_path "$DMG_PATH" 0
fi

notarize_dmg_if_requested

ARCHS=$(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || echo "unknown")
echo "Built app bundle: $APP_BUNDLE"
echo "Built DMG: $DMG_PATH"
echo "Binary architectures: $ARCHS"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  cat <<EOF
Note: build uses ad-hoc signing. For public distribution, set SWIFOTINE_SIGN_IDENTITY to your
Developer ID Application certificate and optionally SWIFOTINE_NOTARIZE=1 to notarize the DMG.
EOF
fi
