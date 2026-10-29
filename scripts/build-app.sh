#!/bin/zsh
# Builds build/AIPassportFlasher.app (release, arm64 + x86_64) with all runtimes bundled.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

[[ -x Vendor/esptool/esptool-arm64 && -x Vendor/esptool/esptool-x86_64 && -x Vendor/esptool/esptool ]] || ./scripts/fetch-esptool.sh
[[ -x Vendor/node/node && -f Vendor/node/LICENSE ]] || ./scripts/fetch-node.sh

ARM_SCRATCH="$ROOT/.build/universal-arm64"
X64_SCRATCH="$ROOT/.build/universal-x86_64"
swift build -c release --arch arm64 --scratch-path "$ARM_SCRATCH"
swift build -c release --arch x86_64 --scratch-path "$X64_SCRATCH"
ARM_BIN="$(swift build -c release --arch arm64 --scratch-path "$ARM_SCRATCH" --show-bin-path)/AIPassportFlasher"
X64_BIN="$(swift build -c release --arch x86_64 --scratch-path "$X64_SCRATCH" --show-bin-path)/AIPassportFlasher"

APP="$ROOT/build/AIPassportFlasher.app"
rm -rf "$APP"
mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Resources/esptool" \
  "$APP/Contents/Resources/node"
lipo -create "$ARM_BIN" "$X64_BIN" -output "$APP/Contents/MacOS/AIPassportFlasher"
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
cp Vendor/esptool/esptool Vendor/esptool/esptool-arm64 Vendor/esptool/esptool-x86_64 \
  Vendor/esptool/LICENSE "$APP/Contents/Resources/esptool/"
cp Vendor/node/node Vendor/node/LICENSE "$APP/Contents/Resources/node/"
chmod 755 "$APP/Contents/Resources/esptool/esptool" \
  "$APP/Contents/Resources/esptool/esptool-arm64" \
  "$APP/Contents/Resources/esptool/esptool-x86_64" \
  "$APP/Contents/Resources/node/node"

SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - --timestamp=none "$APP/Contents/Resources/node/node"
  codesign --force --sign - --timestamp=none "$APP/Contents/Resources/esptool/esptool-arm64"
  codesign --force --sign - --timestamp=none "$APP/Contents/Resources/esptool/esptool-x86_64"
  codesign --force --deep --sign - --timestamp=none "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Resources/node/node"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Resources/esptool/esptool-arm64"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Resources/esptool/esptool-x86_64"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
lipo -info "$APP/Contents/MacOS/AIPassportFlasher"
lipo -info "$APP/Contents/Resources/node/node"
lipo -info "$APP/Contents/Resources/esptool/esptool-arm64"
lipo -info "$APP/Contents/Resources/esptool/esptool-x86_64"
echo "Built $APP"
