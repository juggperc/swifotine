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
    NSColor(calibratedRed: 0.98, green: 0.99, blue: 1.0, alpha: 1.0),
    NSColor(calibratedRed: 0.90, green: 0.95, blue: 1.0, alpha: 1.0),
])!
bgGradient.draw(in: fullRect, angle: -90)

let tileRect = fullRect.insetBy(dx: 92, dy: 92)
let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 190, yRadius: 190)
let tileGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.95, green: 0.99, blue: 1.0, alpha: 0.95),
    NSColor(calibratedRed: 0.78, green: 0.90, blue: 1.0, alpha: 0.88),
    NSColor(calibratedRed: 0.66, green: 0.83, blue: 0.97, alpha: 0.92),
])!
tileGradient.draw(in: tilePath, angle: -90)

NSColor(calibratedRed: 0.38, green: 0.62, blue: 0.80, alpha: 0.34).setStroke()
tilePath.lineWidth = 4.0
tilePath.stroke()

let shinePath = NSBezierPath(roundedRect: tileRect.insetBy(dx: 26, dy: 26), xRadius: 165, yRadius: 165)
let shineGradient = NSGradient(colors: [
    NSColor(calibratedWhite: 1.0, alpha: 0.52),
    NSColor(calibratedWhite: 1.0, alpha: 0.08),
])!
shineGradient.draw(in: shinePath, angle: -90)

let center = NSPoint(x: 512, y: 540)

func wingPath(direction: CGFloat, lift: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: center.x + direction * 6, y: center.y - 14 + lift))
    path.curve(
        to: NSPoint(x: center.x + direction * 300, y: center.y + 146 + lift),
        controlPoint1: NSPoint(x: center.x + direction * 110, y: center.y + 120 + lift),
        controlPoint2: NSPoint(x: center.x + direction * 215, y: center.y + 188 + lift)
    )
    path.curve(
        to: NSPoint(x: center.x + direction * 246, y: center.y + 66 + lift),
        controlPoint1: NSPoint(x: center.x + direction * 280, y: center.y + 116 + lift),
        controlPoint2: NSPoint(x: center.x + direction * 272, y: center.y + 78 + lift)
    )
    path.curve(
        to: NSPoint(x: center.x + direction * 160, y: center.y + 6 + lift),
        controlPoint1: NSPoint(x: center.x + direction * 230, y: center.y + 46 + lift),
        controlPoint2: NSPoint(x: center.x + direction * 198, y: center.y + 12 + lift)
    )
    path.curve(
        to: NSPoint(x: center.x + direction * 66, y: center.y - 46 + lift),
        controlPoint1: NSPoint(x: center.x + direction * 128, y: center.y - 2 + lift),
        controlPoint2: NSPoint(x: center.x + direction * 92, y: center.y - 30 + lift)
    )
    path.curve(
        to: NSPoint(x: center.x + direction * 6, y: center.y - 14 + lift),
        controlPoint1: NSPoint(x: center.x + direction * 34, y: center.y - 54 + lift),
        controlPoint2: NSPoint(x: center.x + direction * 14, y: center.y - 30 + lift)
    )
    path.close()
    return path
}

func tailPath(direction: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: center.x + direction * 2, y: center.y - 62))
    path.curve(
        to: NSPoint(x: center.x + direction * 170, y: center.y - 236),
        controlPoint1: NSPoint(x: center.x + direction * 52, y: center.y - 112),
        controlPoint2: NSPoint(x: center.x + direction * 140, y: center.y - 180)
    )
    path.curve(
        to: NSPoint(x: center.x + direction * 58, y: center.y - 120),
        controlPoint1: NSPoint(x: center.x + direction * 120, y: center.y - 214),
        controlPoint2: NSPoint(x: center.x + direction * 82, y: center.y - 154)
    )
    path.curve(
        to: NSPoint(x: center.x + direction * 2, y: center.y - 62),
        controlPoint1: NSPoint(x: center.x + direction * 36, y: center.y - 92),
        controlPoint2: NSPoint(x: center.x + direction * 16, y: center.y - 72)
    )
    path.close()
    return path
}

let phoenixGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.30, green: 0.76, blue: 0.95, alpha: 0.90),
    NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.84, alpha: 0.94),
    NSColor(calibratedRed: 0.08, green: 0.30, blue: 0.74, alpha: 0.96),
])!

for wing in [wingPath(direction: -1, lift: 0), wingPath(direction: 1, lift: 0)] {
    phoenixGradient.draw(in: wing, angle: -90)
}
for wing in [wingPath(direction: -1, lift: -70), wingPath(direction: 1, lift: -70)] {
    NSColor(calibratedRed: 0.28, green: 0.70, blue: 0.93, alpha: 0.52).setFill()
    wing.fill()
}

let bodyPath = NSBezierPath()
bodyPath.move(to: NSPoint(x: center.x, y: center.y + 170))
bodyPath.curve(
    to: NSPoint(x: center.x + 72, y: center.y + 34),
    controlPoint1: NSPoint(x: center.x + 54, y: center.y + 146),
    controlPoint2: NSPoint(x: center.x + 80, y: center.y + 86)
)
bodyPath.curve(
    to: NSPoint(x: center.x + 12, y: center.y - 74),
    controlPoint1: NSPoint(x: center.x + 54, y: center.y - 6),
    controlPoint2: NSPoint(x: center.x + 26, y: center.y - 42)
)
bodyPath.curve(
    to: NSPoint(x: center.x - 12, y: center.y - 74),
    controlPoint1: NSPoint(x: center.x + 4, y: center.y - 84),
    controlPoint2: NSPoint(x: center.x - 4, y: center.y - 84)
)
bodyPath.curve(
    to: NSPoint(x: center.x - 72, y: center.y + 34),
    controlPoint1: NSPoint(x: center.x - 26, y: center.y - 42),
    controlPoint2: NSPoint(x: center.x - 54, y: center.y - 6)
)
bodyPath.curve(
    to: NSPoint(x: center.x, y: center.y + 170),
    controlPoint1: NSPoint(x: center.x - 80, y: center.y + 86),
    controlPoint2: NSPoint(x: center.x - 54, y: center.y + 146)
)
bodyPath.close()
phoenixGradient.draw(in: bodyPath, angle: -90)

for plume in [tailPath(direction: -1), tailPath(direction: 1)] {
    NSColor(calibratedRed: 0.16, green: 0.58, blue: 0.88, alpha: 0.86).setFill()
    plume.fill()
}

let noteFont = NSFont.systemFont(ofSize: 540, weight: .bold)
let noteShadow = NSShadow()
noteShadow.shadowBlurRadius = 18
noteShadow.shadowOffset = NSSize(width: 0, height: -2)
noteShadow.shadowColor = NSColor(calibratedRed: 0.04, green: 0.21, blue: 0.45, alpha: 0.28)

let noteAttributes: [NSAttributedString.Key: Any] = [
    .font: noteFont,
    .foregroundColor: NSColor(calibratedRed: 0.90, green: 0.98, blue: 1.0, alpha: 0.84),
    .shadow: noteShadow
]
let noteHighlightAttributes: [NSAttributedString.Key: Any] = [
    .font: noteFont,
    .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.34)
]

let note = NSAttributedString(string: "♪", attributes: noteAttributes)
let noteSize = note.size()
let noteOrigin = NSPoint(
    x: (size.width - noteSize.width) / 2.0 + 8,
    y: (size.height - noteSize.height) / 2.0 - 28
)
note.draw(at: noteOrigin)
NSAttributedString(string: "♪", attributes: noteHighlightAttributes).draw(
    at: NSPoint(x: noteOrigin.x - 9, y: noteOrigin.y + 12))

let bubbleCenters: [NSPoint] = [
    NSPoint(x: 406, y: 674),
    NSPoint(x: 464, y: 636),
    NSPoint(x: 606, y: 590),
    NSPoint(x: 560, y: 444),
    NSPoint(x: 430, y: 402),
    NSPoint(x: 642, y: 478),
]
let bubbleSizes: [CGFloat] = [11, 16, 13, 20, 14, 10]

for (index, centerPoint) in bubbleCenters.enumerated() {
    let diameter = bubbleSizes[index]
    let bubbleRect = NSRect(
        x: centerPoint.x - diameter / 2.0,
        y: centerPoint.y - diameter / 2.0,
        width: diameter,
        height: diameter
    )
    let bubblePath = NSBezierPath(ovalIn: bubbleRect)
    NSColor(calibratedWhite: 1.0, alpha: 0.24).setFill()
    bubblePath.fill()
    NSColor(calibratedWhite: 1.0, alpha: 0.46).setStroke()
    bubblePath.lineWidth = 1.0
    bubblePath.stroke()
}

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
