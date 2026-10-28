#!/bin/bash
# Installs or updates TakoKey, no Homebrew needed:
#   curl -fsSL https://raw.githubusercontent.com/bvpotapenko/takokey/main/install.sh | bash
# Files curl downloads get no quarantine flag, so macOS doesn't ask "Open Anyway".
set -euo pipefail

if [ "$(uname -m)" != arm64 ]; then echo "TakoKey needs a Mac with Apple silicon."; exit 1; fi

tmp=$(mktemp -d)
trap 'hdiutil detach -quiet "$tmp/mnt" 2>/dev/null || true; rm -rf "$tmp"' EXIT

echo "Downloading the latest TakoKey…"
curl -fsSL -o "$tmp/TakoKey.dmg" https://github.com/bvpotapenko/takokey/releases/latest/download/TakoKey.dmg
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$tmp/mnt" "$tmp/TakoKey.dmg"

pkill -x TakoKey || true # a running copy keeps the old version and holds the shortcuts
sleep 1
rm -rf /Applications/TakoKey.app
ditto "$tmp/mnt/TakoKey.app" /Applications/TakoKey.app
open /Applications/TakoKey.app
echo "Done: TakoKey is in Applications and running. Look for the keyboard icon in the menu bar."