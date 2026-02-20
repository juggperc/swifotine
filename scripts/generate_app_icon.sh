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
let bgGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.08, alpha: 1.0),
    NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.11, alpha: 1.0),
])!
bgGradient.draw(in: fullRect, angle: -90)

let tileRect = fullRect.insetBy(dx: 88, dy: 88)
let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 210, yRadius: 210)
let tileGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.22, alpha: 1.0),
    NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.16, alpha: 1.0),
    NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.12, alpha: 1.0),
])!
tileGradient.draw(in: tilePath, angle: -90)

NSColor(calibratedRed: 0.32, green: 0.52, blue: 0.82, alpha: 0.30).setStroke()
tilePath.lineWidth = 3.0
tilePath.stroke()

let glossPath = NSBezierPath(roundedRect: tileRect.insetBy(dx: 26, dy: 26), xRadius: 184, yRadius: 184)
let glossGradient = NSGradient(colors: [
    NSColor(calibratedWhite: 1.0, alpha: 0.28),
    NSColor(calibratedWhite: 1.0, alpha: 0.03),
])!
glossGradient.draw(in: glossPath, angle: -90)

let centerGlowRect = NSRect(x: 198, y: 216, width: 628, height: 628)
let centerGlowPath = NSBezierPath(ovalIn: centerGlowRect)
let centerGlow = NSGradient(colors: [
    NSColor(calibratedRed: 0.13, green: 0.33, blue: 0.74, alpha: 0.44),
    NSColor(calibratedRed: 0.13, green: 0.33, blue: 0.74, alpha: 0.0),
])!
centerGlow.draw(in: centerGlowPath, relativeCenterPosition: .zero)

let center = NSPoint(x: 512, y: 530)

func wingPath(direction: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: center.x + direction * 8, y: center.y + 14))
    path.curve(
        to: NSPoint(x: center.x + direction * 286, y: center.y + 138),
        controlPoint1: NSPoint(x: center.x + direction * 96, y: center.y + 132),
        controlPoint2: NSPoint(x: center.x + direction * 218, y: center.y + 182)
    )
    path.curve(
        to: NSPoint(x: center.x + direction * 186, y: center.y - 12),
        controlPoint1: NSPoint(x: center.x + direction * 262, y: center.y + 90),
        controlPoint2: NSPoint(x: center.x + direction * 220, y: center.y + 18)
    )
    path.curve(
        to: NSPoint(x: center.x + direction * 8, y: center.y + 14),
        controlPoint1: NSPoint(x: center.x + direction * 126, y: center.y - 26),
        controlPoint2: NSPoint(x: center.x + direction * 54, y: center.y - 6)
    )
    path.close()
    return path
}

func tailPath(direction: CGFloat, yOffset: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: center.x + direction * 6, y: center.y - 68 + yOffset))
    path.curve(
        to: NSPoint(x: center.x + direction * 176, y: center.y - 248 + yOffset),
        controlPoint1: NSPoint(x: center.x + direction * 52, y: center.y - 120 + yOffset),
        controlPoint2: NSPoint(x: center.x + direction * 132, y: center.y - 204 + yOffset)
    )
    path.curve(
        to: NSPoint(x: center.x + direction * 56, y: center.y - 110 + yOffset),
        controlPoint1: NSPoint(x: center.x + direction * 120, y: center.y - 226 + yOffset),
        controlPoint2: NSPoint(x: center.x + direction * 84, y: center.y - 156 + yOffset)
    )
    path.curve(
        to: NSPoint(x: center.x + direction * 6, y: center.y - 68 + yOffset),
        controlPoint1: NSPoint(x: center.x + direction * 34, y: center.y - 86 + yOffset),
        controlPoint2: NSPoint(x: center.x + direction * 16, y: center.y - 74 + yOffset)
    )
    path.close()
    return path
}

let phoenixGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.31, green: 0.76, blue: 0.98, alpha: 0.96),
    NSColor(calibratedRed: 0.14, green: 0.50, blue: 0.94, alpha: 0.96),
    NSColor(calibratedRed: 0.08, green: 0.34, blue: 0.83, alpha: 0.96),
])!

for wing in [wingPath(direction: -1), wingPath(direction: 1)] {
    phoenixGradient.draw(in: wing, angle: -90)
}

let bodyPath = NSBezierPath()
bodyPath.move(to: NSPoint(x: center.x, y: center.y + 168))
bodyPath.curve(
    to: NSPoint(x: center.x + 64, y: center.y + 38),
    controlPoint1: NSPoint(x: center.x + 48, y: center.y + 136),
    controlPoint2: NSPoint(x: center.x + 74, y: center.y + 90)
)
bodyPath.curve(
    to: NSPoint(x: center.x + 12, y: center.y - 82),
    controlPoint1: NSPoint(x: center.x + 50, y: center.y - 4),
    controlPoint2: NSPoint(x: center.x + 28, y: center.y - 50)
)
bodyPath.curve(
    to: NSPoint(x: center.x - 12, y: center.y - 82),
    controlPoint1: NSPoint(x: center.x + 4, y: center.y - 92),
    controlPoint2: NSPoint(x: center.x - 4, y: center.y - 92)
)
bodyPath.curve(
    to: NSPoint(x: center.x - 64, y: center.y + 38),
    controlPoint1: NSPoint(x: center.x - 28, y: center.y - 50),
    controlPoint2: NSPoint(x: center.x - 50, y: center.y - 4)
)
bodyPath.curve(
    to: NSPoint(x: center.x, y: center.y + 168),
    controlPoint1: NSPoint(x: center.x - 74, y: center.y + 90),
    controlPoint2: NSPoint(x: center.x - 48, y: center.y + 136)
)
bodyPath.close()
phoenixGradient.draw(in: bodyPath, angle: -90)

for plume in [tailPath(direction: -1, yOffset: 0), tailPath(direction: 1, yOffset: 0)] {
    NSColor(calibratedRed: 0.14, green: 0.55, blue: 0.92, alpha: 0.88).setFill()
    plume.fill()
}
for plume in [tailPath(direction: -1, yOffset: -38), tailPath(direction: 1, yOffset: -38)] {
    NSColor(calibratedRed: 0.12, green: 0.44, blue: 0.82, alpha: 0.64).setFill()
    plume.fill()
}

let noteFont = NSFont.systemFont(ofSize: 500, weight: .semibold)
let noteShadow = NSShadow()
noteShadow.shadowBlurRadius = 18
noteShadow.shadowOffset = NSSize(width: 0, height: -2)
noteShadow.shadowColor = NSColor(calibratedRed: 0.02, green: 0.13, blue: 0.30, alpha: 0.42)

let noteAttributes: [NSAttributedString.Key: Any] = [
    .font: noteFont,
    .foregroundColor: NSColor(calibratedRed: 0.86, green: 0.97, blue: 1.0, alpha: 0.90),
    .shadow: noteShadow
]
let noteHighlightAttributes: [NSAttributedString.Key: Any] = [
    .font: noteFont,
    .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.24)
]

let note = NSAttributedString(string: "♪", attributes: noteAttributes)
let noteSize = note.size()
let noteOrigin = NSPoint(
    x: (size.width - noteSize.width) / 2.0 + 6,
    y: (size.height - noteSize.height) / 2.0 - 24
)
note.draw(at: noteOrigin)
NSAttributedString(string: "♪", attributes: noteHighlightAttributes).draw(
    at: NSPoint(x: noteOrigin.x - 8, y: noteOrigin.y + 9))

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
