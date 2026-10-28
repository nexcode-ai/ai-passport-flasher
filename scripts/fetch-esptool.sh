#!/bin/zsh
# Downloads the official standalone esptool (PyInstaller build, no Python needed)
# into Vendor/esptool and verifies the archive checksum.
set -euo pipefail

VERSION="v5.6.0"
ASSET="esptool-${VERSION}-macos-arm64.tar.gz"
SHA256="08a58829a3f14bb08f2e39f4cad48dcb14b7000384268e7f06689836332d6e25"
URL="https://github.com/espressif/esptool/releases/download/${VERSION}/${ASSET}"

ROOT="${0:A:h:h}"
DEST="$ROOT/Vendor/esptool"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ -x "$DEST/esptool" ]] && "$DEST/esptool" version 2>/dev/null | grep -q "${VERSION#v}"; then
  echo "esptool ${VERSION} already present at $DEST"
  exit 0
fi

echo "Downloading $URL"
curl -fL --retry 3 -o "$TMP/$ASSET" "$URL"
echo "$SHA256  $TMP/$ASSET" | shasum -a 256 -c -
tar -xzf "$TMP/$ASSET" -C "$TMP"
mkdir -p "$DEST"
cp "$TMP/esptool-macos-arm64/esptool" "$TMP/esptool-macos-arm64/LICENSE" "$DEST/"
chmod +x "$DEST/esptool"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
"$DEST/esptool" version
