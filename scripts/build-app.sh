#!/bin/zsh
# Builds build/AIPassportFlasher.app (release, arm64) with esptool bundled.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

[[ -x Vendor/esptool/esptool ]] || ./scripts/fetch-esptool.sh

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/AIPassportFlasher"

APP="$ROOT/build/AIPassportFlasher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/esptool"
cp "$BIN" "$APP/Contents/MacOS/AIPassportFlasher"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/" && \
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null
# esptool keeps Espressif's own Developer ID signature; it is sealed as a resource.
cp Vendor/esptool/esptool Vendor/esptool/LICENSE "$APP/Contents/Resources/esptool/"

codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
