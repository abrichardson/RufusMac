#!/usr/bin/env bash
# Sign via MACUS_SIGN_IDENTITY at build time. Credentials stay in Keychain.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
: "${MACUS_SIGN_IDENTITY:?Set the Developer ID Application signing identity}"
: "${MACUS_NOTARY_PROFILE:?Set the notarytool Keychain profile name}"
APP="$ROOT/dist/Macus.app"
DMG="$ROOT/dist/Macus.dmg"
mkdir -p dist/notarization
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" dist/notarization/Macus-submit.zip
xcrun notarytool submit dist/notarization/Macus-submit.zip --keychain-profile "$MACUS_NOTARY_PROFILE" --wait --output-format json > dist/notarization/app-result.json
python3 -c 'import json; assert json.load(open("dist/notarization/app-result.json"))["status"] == "Accepted", "App notarization not accepted"'
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
STAGING=$(mktemp -d /tmp/macus-notarized.XXXXXX)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname Macus -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$MACUS_SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$MACUS_NOTARY_PROFILE" --wait --output-format json > dist/notarization/dmg-result.json
python3 -c 'import json; assert json.load(open("dist/notarization/dmg-result.json"))["status"] == "Accepted", "DMG notarization not accepted"'
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
# Stapling changes package bytes: generate distribution checksums only afterward.
(cd dist && shasum -a 256 Macus.dmg > Macus.dmg.sha256)
echo 'Notarized app and DMG ready. Create the release ZIP from the stapled app.'
