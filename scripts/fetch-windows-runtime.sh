#!/bin/zsh
# Downloads the official Windows esptool and Node runtimes used by the shared desktop app.
set -euo pipefail

ROOT="${0:A:h:h}"
DEST="$ROOT/Vendor/win"
NODE_VERSION="v24.16.0"
ESPTOOL_VERSION="v5.6.0"
ESPTOOL_SHA="d55a96fbeb97fd4cb05bd93f201e5c8f6518b7bfcde2fc6966fd0190fd891629"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$DEST"

if [[ ! -x "$DEST/node.exe" && ! -f "$DEST/node.exe" ]]; then
  ARCHIVE="node-${NODE_VERSION}-win-x64.zip"
  curl -fL --retry 3 -o "$TMP/SHASUMS256.txt" "https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt"
  curl -fL --retry 3 -o "$TMP/$ARCHIVE" "https://nodejs.org/dist/${NODE_VERSION}/${ARCHIVE}"
  EXPECTED="$(awk -v file="$ARCHIVE" '$2 == file { print $1 }' "$TMP/SHASUMS256.txt")"
  echo "$EXPECTED  $TMP/$ARCHIVE" | shasum -a 256 -c -
  unzip -q "$TMP/$ARCHIVE" -d "$TMP"
  cp "$TMP/node-${NODE_VERSION}-win-x64/node.exe" "$DEST/node.exe"
fi

if [[ ! -f "$DEST/esptool.exe" ]]; then
  ASSET="esptool-${ESPTOOL_VERSION}-windows-amd64.zip"
  curl -fL --retry 3 -o "$TMP/$ASSET" "https://github.com/espressif/esptool/releases/download/${ESPTOOL_VERSION}/${ASSET}"
  if [[ "$ESPTOOL_SHA" != __ESPTOOL_SHA__ ]]; then
    echo "$ESPTOOL_SHA  $TMP/$ASSET" | shasum -a 256 -c -
  fi
  unzip -q "$TMP/$ASSET" -d "$TMP/esptool"
  EXE="$(find "$TMP/esptool" -name esptool.exe -print -quit)"
  cp "$EXE" "$DEST/esptool.exe"
fi

echo "Windows runtime ready at $DEST"
