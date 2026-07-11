#!/usr/bin/env bash
# Builds WebBridge and wraps the release binary into a double-clickable WebBridge.app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Building release binary…"
swift build -c release

APP="$ROOT/build/WebBridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/.build/release/WebBridge" "$APP/Contents/MacOS/WebBridge"
cp "$ROOT/Sources/WebBridge/Info.plist" "$APP/Contents/Info.plist"

ICNS="$ROOT/icon/AppIcon.icns"
if [ ! -f "$ICNS" ] && command -v rsvg-convert >/dev/null 2>&1; then
  echo "Generating app icon…"
  "$ROOT/scripts/make-icon.sh"
fi
if [ -f "$ICNS" ]; then
  cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
else
  echo "warning: icon/AppIcon.icns missing and rsvg-convert unavailable; app will have no icon." >&2
fi

echo "Built $APP"
echo "Run it with: open \"$APP\""
