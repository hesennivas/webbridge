#!/usr/bin/env bash
# webbridge installer — builds the app from source and drops it in /Applications.
#
# run it straight from wherever this site is hosted:
#   curl -fsSL <host>/install.sh | bash
#
# pin a version:  WEBBRIDGE_VERSION=v0.0.1 curl -fsSL <host>/install.sh | bash
# needs the xcode 26 command line tools (swift 6). curl sets no quarantine
# xattr, so the built app opens without a gatekeeper prompt.
set -euo pipefail

VERSION="${WEBBRIDGE_VERSION:-v0.0.1}"
REPO="https://github.com/hesennivas/webbridge"
APP="/Applications/WebBridge.app"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "webbridge is macOS only."
command -v git   >/dev/null 2>&1 || die "git is required (install the xcode command line tools: xcode-select --install)."
command -v swift >/dev/null 2>&1 || die "the swift toolchain is required (xcode 26 or its command line tools)."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "cloning webbridge $VERSION…"
git clone --depth 1 --branch "$VERSION" "$REPO" "$TMP/src" >/dev/null 2>&1 \
  || die "could not clone $REPO at tag $VERSION."
cd "$TMP/src"

say "building the release binary (this takes a few minutes)…"
swift build --disable-sandbox -c release

say "assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/WebBridge     "$APP/Contents/MacOS/WebBridge"
cp Sources/WebBridge/Info.plist "$APP/Contents/Info.plist"
cp icon/AppIcon.icns            "$APP/Contents/Resources/AppIcon.icns"

say "installed → $APP"
echo "open it with:  open \"$APP\""
