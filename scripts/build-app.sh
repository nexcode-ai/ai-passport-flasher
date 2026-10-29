#!/bin/zsh
# Builds build/AIPassportFlasher.app (release, arm64) with all runtimes bundled.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

[[ -x Vendor/esptool/esptool ]] || ./scripts/fetch-esptool.sh
[[ -x Vendor/node/node && -f Vendor/node/LICENSE ]] || ./scripts/fetch-node.sh

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/AIPassportFlasher"

APP="$ROOT/build/AIPassportFlasher.app"
rm -rf "$APP"
mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Resources/esptool" \
  "$APP/Contents/Resources/node"
cp "$BIN" "$APP/Contents/MacOS/AIPassportFlasher"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :APFCommit string $(git rev-parse --short HEAD)" \
  "$APP/Contents/Info.plist" >/dev/null
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/" && \
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null
if [[ -d Resources/Assets.xcassets ]]; then
  xcrun actool Resources/Assets.xcassets \
    --compile "$APP/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ROOT/build/AppIconAssetInfo.plist" \
    --output-format human-readable-text
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist" >/dev/null
fi
[[ -d Resources/Simulator ]] && ditto Resources/Simulator "$APP/Contents/Resources/simulator"
cp Vendor/esptool/esptool Vendor/esptool/LICENSE "$APP/Contents/Resources/esptool/"
cp Vendor/node/node Vendor/node/LICENSE "$APP/Contents/Resources/node/"
chmod 755 "$APP/Contents/Resources/esptool/esptool" "$APP/Contents/Resources/node/node"

SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - --timestamp=none "$APP/Contents/Resources/node/node"
  codesign --force --sign - --timestamp=none "$APP/Contents/Resources/esptool/esptool"
  codesign --force --deep --sign - --timestamp=none "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Resources/node/node"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Resources/esptool/esptool"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP"
