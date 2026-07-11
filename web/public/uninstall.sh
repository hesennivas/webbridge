#!/usr/bin/env bash
# webbridge uninstaller.
#
#   curl -fsSL <host>/uninstall.sh | bash
set -euo pipefail

APP="/Applications/WebBridge.app"
if [ -d "$APP" ]; then
  rm -rf "$APP"
  printf '\033[1mremoved %s\033[0m\n' "$APP"
else
  echo "nothing to do - $APP is not installed."
fi
