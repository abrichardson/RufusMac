#!/usr/bin/env bash
set -euo pipefail

# make_dmg.sh — build Macus.app and package it into a portable Macus.dmg
# with a drag-to-Applications layout, plus a published SHA-256.
# Uses only built-in tools (hdiutil); no third-party installers required.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/build_app.sh" release

APP="$ROOT/dist/Macus.app"
DMG="$ROOT/dist/Macus.dmg"
STAGING="$ROOT/build/dmg"

echo "▶ Staging DMG contents…"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "▶ Creating $DMG …"
rm -f "$DMG"
hdiutil create -volname "Macus" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

echo "▶ Checksum:"
( cd "$ROOT/dist" && shasum -a 256 "Macus.dmg" | tee "Macus.dmg.sha256" )

echo "✅ Portable disk image ready: $DMG"
