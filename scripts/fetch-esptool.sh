#!/bin/zsh
# Downloads the official standalone esptool builds (PyInstaller, no Python needed)
# for Apple Silicon and Intel into Vendor/esptool and verifies the archive checksums.
# PyInstaller one-file executables cannot be merged with lipo, so Vendor/esptool/esptool
# is a launcher that runs the build matching the current process architecture.
set -euo pipefail

VERSION="v5.6.0"
typeset -A SHA256=(
  arm64 08a58829a3f14bb08f2e39f4cad48dcb14b7000384268e7f06689836332d6e25
  amd64 23921776a7df75f2e6f3ca10a604d74db4661e1b8a0ebb89bdddcd2d26f37055
)
typeset -A SLICE=(arm64 arm64 amd64 x86_64)

ROOT="${0:A:h:h}"
DEST="$ROOT/Vendor/esptool"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ -x "$DEST/esptool-arm64" && -x "$DEST/esptool-x86_64" ]] \
  && "$DEST/esptool-arm64" version 2>/dev/null | grep -q "${VERSION#v}"; then
  echo "esptool ${VERSION} already present at $DEST"
  exit 0
fi

rm -rf "$DEST"
mkdir -p "$DEST"
for platform in arm64 amd64; do
  asset="esptool-${VERSION}-macos-${platform}.tar.gz"
  url="https://github.com/espressif/esptool/releases/download/${VERSION}/${asset}"
  echo "Downloading $url"
  curl -fL --retry 3 -o "$TMP/$asset" "$url"
  echo "${SHA256[$platform]}  $TMP/$asset" | shasum -a 256 -c -
  tar -xzf "$TMP/$asset" -C "$TMP"
  cp "$TMP/esptool-macos-${platform}/esptool" "$DEST/esptool-${SLICE[$platform]}"
  cp "$TMP/esptool-macos-${platform}/LICENSE" "$DEST/LICENSE"
done

cat > "$DEST/esptool" <<'EOF'
#!/bin/sh
exec "$(dirname "$0")/esptool-$(/usr/bin/uname -m)" "$@"
EOF
chmod +x "$DEST"/esptool*
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
"$DEST/esptool" version
