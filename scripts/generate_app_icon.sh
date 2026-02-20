#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/assets"
ICONSET_DIR="$ASSETS_DIR/AppIcon.iconset"
BASE_PNG="$ASSETS_DIR/AppIcon-base-1024.png"
ICNS_OUT="$ASSETS_DIR/AppIcon.icns"
SWIFT_SCRIPT="$ASSETS_DIR/.draw_swifotine_icon.swift"

mkdir -p "$ASSETS_DIR"

cat > "$SWIFT_SCRIPT" <<'SWIFT'
import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()

let fullRect = NSRect(origin: .zero, size: size)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.05, green: 0.12, blue: 0.35, alpha: 1.0),
    NSColor(calibratedRed: 0.07, green: 0.46, blue: 0.78, alpha: 1.0)
])!
gradient.draw(in: fullRect, angle: 90)

let glassRect = fullRect.insetBy(dx: 92, dy: 92)
let glassPath = NSBezierPath(roundedRect: glassRect, xRadius: 210, yRadius: 210)
NSColor(calibratedWhite: 1.0, alpha: 0.14).setFill()
glassPath.fill()

let innerRect = fullRect.insetBy(dx: 140, dy: 140)
let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: 170, yRadius: 170)
NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.22, alpha: 0.55).setFill()
innerPath.fill()

let noteText = "♫"
let noteFont = NSFont.systemFont(ofSize: 530, weight: .bold)
let noteAttributes: [NSAttributedString.Key: Any] = [
    .font: noteFont,
    .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.96)
]

let attributed = NSAttributedString(string: noteText, attributes: noteAttributes)
let noteSize = attributed.size()
let noteOrigin = NSPoint(x: (size.width - noteSize.width) / 2.0,
                         y: (size.height - noteSize.height) / 2.0 - 40)
attributed.draw(at: noteOrigin)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [.compressionFactor: 1.0])
else {
    fputs("Failed to generate icon image data\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
try png.write(to: URL(fileURLWithPath: outputPath))
SWIFT

swift "$SWIFT_SCRIPT" "$BASE_PNG"
rm -f "$SWIFT_SCRIPT"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$BASE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  scale2=$((size * 2))
  sips -z "$scale2" "$scale2" "$BASE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_OUT"

echo "Generated icon: $ICNS_OUT"
