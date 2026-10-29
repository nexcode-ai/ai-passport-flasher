#!/bin/zsh
# Fetches the pinned official Apple Silicon Node runtime used by the simulator.
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${APF_NODE_VERSION:-v24.16.0}"
ARCHIVE="node-${VERSION}-darwin-arm64.tar.gz"
EXPECTED_SHA256="39189dab4eeb15706c424af0ac08a3044c9e48f7db12a7d77f6b7aafc7dd5df6"
DEST="$ROOT/Vendor/node"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

if [[ "$VERSION" != "v24.16.0" ]]; then
  print -u2 "APF_NODE_VERSION requires a matching pinned checksum in scripts/fetch-node.sh"
  exit 1
fi

curl -fsSL --retry 3 \
  "https://nodejs.org/dist/${VERSION}/${ARCHIVE}" \
  -o "$TEMP/$ARCHIVE"

ACTUAL_SHA256="$(shasum -a 256 "$TEMP/$ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  print -u2 "Node runtime checksum mismatch"
  exit 1
fi

tar -xzf "$TEMP/$ARCHIVE" -C "$TEMP"
SOURCE="$TEMP/node-${VERSION}-darwin-arm64"
mkdir -p "$DEST"
cp "$SOURCE/bin/node" "$DEST/node"
cp "$SOURCE/LICENSE" "$DEST/LICENSE"
chmod 755 "$DEST/node"

echo "Fetched Node ${VERSION} for arm64"
