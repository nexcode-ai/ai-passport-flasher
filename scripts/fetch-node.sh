#!/bin/zsh
# Fetches the pinned official Node runtime for Apple Silicon and Intel and merges
# them into one universal binary used by the simulator.
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="v24.16.0"
typeset -A SHA256=(
  arm64 39189dab4eeb15706c424af0ac08a3044c9e48f7db12a7d77f6b7aafc7dd5df6
  x64 298b4c7b3cb80765c8703e42b90324a4ece3b6634947b89e769c3c980ab55185
)
DEST="$ROOT/Vendor/node"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

for platform in arm64 x64; do
  archive="node-${VERSION}-darwin-${platform}.tar.gz"
  curl -fsSL --retry 3 "https://nodejs.org/dist/${VERSION}/${archive}" -o "$TEMP/$archive"
  echo "${SHA256[$platform]}  $TEMP/$archive" | shasum -a 256 -c -
  tar -xzf "$TEMP/$archive" -C "$TEMP"
done

mkdir -p "$DEST"
lipo -create \
  "$TEMP/node-${VERSION}-darwin-arm64/bin/node" \
  "$TEMP/node-${VERSION}-darwin-x64/bin/node" \
  -output "$DEST/node"
cp "$TEMP/node-${VERSION}-darwin-arm64/LICENSE" "$DEST/LICENSE"
chmod 755 "$DEST/node"
lipo -info "$DEST/node"
