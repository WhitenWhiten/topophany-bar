#!/bin/sh
# Usage: shot.sh PAGE?QUERY OUT.png WIDTH HEIGHT
CH="$HOME/Library/Caches/ms-playwright/chromium_headless_shell-1248/chrome-headless-shell-mac-arm64/chrome-headless-shell"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$CH" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor="${5:-1}" --virtual-time-budget=1500 \
  --window-size="$3,$4" --screenshot="$2" "file://$DIR/$1" >/dev/null 2>&1
echo "$2"
