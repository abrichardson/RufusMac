#!/usr/bin/env bash
set -euo pipefail

# make_icon.sh — generate Assets/AppIcon.icns (a teal Liquid-Glass-style squircle
# with a white drive glyph) using AppKit + sips + iconutil. No design tools needed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
ICONSET="$BUILD/AppIcon.iconset"
MASTER="$BUILD/icon_1024.png"
SWIFT_SRC="$BUILD/make_icon.swift"
mkdir -p "$BUILD" "$ICONSET" "$ROOT/Assets"

cat > "$SWIFT_SRC" <<'SWIFT'
import AppKit

let side: CGFloat = 1024
let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: side, height: side)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 224, yRadius: 224)
squircle.addClip()

let gradient = NSGradient(
    starting: NSColor(srgbRed: 0.29, green: 0.46, blue: 0.99, alpha: 1),
    ending:   NSColor(srgbRed: 0.10, green: 0.16, blue: 0.43, alpha: 1)
)!
gradient.draw(in: rect, angle: -45)

// Soft top highlight for a glassy feel.
let highlight = NSGradient(
    starting: NSColor(white: 1, alpha: 0.28),
    ending:   NSColor(white: 1, alpha: 0.0)
)!
highlight.draw(in: NSRect(x: 0, y: side * 0.5, width: side, height: side * 0.5), angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 560, weight: .bold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "externaldrive.fill.badge.plus", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    let r = NSRect(x: (side - s.width) / 2, y: (side - s.height) / 2, width: s.width, height: s.height)
    symbol.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1.0)
}

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else { FileHandle.standardError.write(Data("icon render failed\n".utf8)); exit(1) }

try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

echo "▶ Rendering master icon…"
swift "$SWIFT_SRC" "$MASTER"

echo "▶ Generating iconset…"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  dbl=$((size * 2))
  sips -z "$dbl" "$dbl" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

echo "▶ Building AppIcon.icns…"
iconutil -c icns "$ICONSET" -o "$ROOT/Assets/AppIcon.icns"
echo "✅ Wrote $ROOT/Assets/AppIcon.icns"
