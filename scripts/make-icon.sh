#!/usr/bin/env bash
# Renders icon/AppIcon.svg into a macOS iconset and AppIcon.icns.
# Requires rsvg-convert (brew install librsvg) and iconutil (ships with macOS).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SVG="$ROOT/icon/AppIcon.svg"
OUT="$ROOT/icon/AppIcon.icns"
PREVIEW="$ROOT/icon/AppIcon-1024.png"
SET="$(mktemp -d)/AppIcon.iconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "error: rsvg-convert not found. Install it with: brew install librsvg" >&2
  exit 1
fi

mkdir -p "$SET"

render() { rsvg-convert -w "$1" -h "$1" "$SVG" -o "$2"; }

echo "Rendering iconset from $SVG…"
render 16   "$SET/icon_16x16.png"
render 32   "$SET/icon_16x16@2x.png"
render 32   "$SET/icon_32x32.png"
render 64   "$SET/icon_32x32@2x.png"
render 128  "$SET/icon_128x128.png"
render 256  "$SET/icon_128x128@2x.png"
render 256  "$SET/icon_256x256.png"
render 512  "$SET/icon_256x256@2x.png"
render 512  "$SET/icon_512x512.png"
render 1024 "$SET/icon_512x512@2x.png"

echo "Packing $OUT…"
iconutil -c icns "$SET" -o "$OUT"

render 1024 "$PREVIEW"

rm -rf "$(dirname "$SET")"
echo "Wrote $OUT and $PREVIEW"
