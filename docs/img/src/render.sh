#!/bin/sh
# Render each diagram HTML in this folder to ../<name>.png (2x scale).
# Usage: docs/img/src/render.sh
cd "$(dirname "$0")"
BRAVE="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
for f in *.html; do
  n="${f%.html}"
  size=$(grep -o 'data-size="[0-9]*,[0-9]*"' "$f" | cut -d'"' -f2)
  "$BRAVE" --headless=new --hide-scrollbars --force-device-scale-factor=2 \
    --virtual-time-budget=4000 --window-size="$size" \
    --screenshot="$PWD/../$n.png" "file://$PWD/$f" 2>/dev/null
  echo "rendered ../$n.png"
done
