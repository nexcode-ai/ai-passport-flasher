#!/bin/zsh
# Renders every screen of build/AIPassportFlasher.app to screenshots/*.png in the
# background (no serial access, no writes). Usage: scripts/snapshots.sh [play-slug]
# Passing a slug downloads that play's firmware once (counted by the site).
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/AIPassportFlasher.app"
OUT="${APF_OUT:-$ROOT/screenshots}"
SAMPLES="$(mktemp -d)"
trap 'rm -rf "$SAMPLES"' EXIT

[[ -d "$APP" ]] || "$ROOT/scripts/build-app.sh"
BASE="https://ai-passport.folotoy.cn/assets/firmwares/ai-passport-default"
for f in bootloader.bin partition-table.bin trae_card.bin; do
  curl -fsS -o "$SAMPLES/$f" "$BASE/$f"
done

rm -rf "$OUT"
open -g -n -W \
  --env APF_SNAPSHOT_DIR="$OUT" \
  --env APF_SAMPLE_PLAY_SLUG="${1:-}" \
  --env APF_SAMPLE_MERGED="$SAMPLES/trae_card.bin" \
  --env APF_SAMPLE_PARTS="$SAMPLES/bootloader.bin:$SAMPLES/partition-table.bin:$SAMPLES/trae_card.bin" \
  "$APP"
ls "$OUT"
