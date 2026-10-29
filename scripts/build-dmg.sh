#!/bin/zsh
# Builds a drag-to-Applications DMG. Developer ID signing/notarization is optional.
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/AIPassportFlasher.app"
DIST="$ROOT/dist"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

"$ROOT/scripts/build-app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/AIPassportFlasher-${VERSION}-arm64.dmg"
mkdir -p "$DIST"
rm -f "$DMG"

ditto "$APP" "$STAGING/AIPassportFlasher.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "AI Passport 刷机工具" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

echo "Built $DMG"
