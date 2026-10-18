#!/bin/sh
# Renders the app icon from design/assets/mark.svg: the globe on the TUI's
# ink, in a macOS squircle on the 824/1024 grid. Needs headless Chrome.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CH="${CHROME:-$HOME/Library/Caches/ms-playwright/chromium_headless_shell-1248/chrome-headless-shell-mac-arm64/chrome-headless-shell}"
OUT="$ROOT/Apps/topophany-bar/Assets.xcassets/AppIcon.appiconset"
TMP="$(mktemp -d)"
cp "$ROOT/design/assets/mark.svg" "$TMP/"
cat > "$TMP/icon.html" <<'HTML'
<!doctype html><meta charset="utf-8"><style>
html,body{margin:0;width:1024px;height:1024px;background:transparent}
.sq{position:absolute;left:100px;top:100px;width:824px;height:824px;border-radius:185px;
 background:radial-gradient(120% 100% at 30% 18%,#1d3444 0%,#0f1d28 45%,#070c11 100%);
 box-shadow:0 10px 24px rgba(0,0,0,.28), inset 0 0 0 2px rgba(143,245,226,.10), inset 0 2px 0 rgba(255,255,255,.08)}
.glow{position:absolute;left:162px;top:162px;width:700px;height:700px;border-radius:50%;
 background:radial-gradient(circle,rgba(94,234,212,.20) 0%,rgba(94,234,212,0) 65%)}
img{position:absolute;left:222px;top:222px;width:580px;height:580px;filter:drop-shadow(0 6px 18px rgba(0,0,0,.45))}
</style><div class="sq"></div><div class="glow"></div><img src="mark.svg">
HTML
"$CH" --headless --disable-gpu --hide-scrollbars --default-background-color=00000000 --window-size=1024,1024 \
  --screenshot="$TMP/icon-1024.png" "file://$TMP/icon.html" >/dev/null 2>&1
mkdir -p "$OUT"
for s in 16 32 64 128 256 512 1024; do sips -z $s $s "$TMP/icon-1024.png" --out "$OUT/icon-$s.png" >/dev/null; done
cat > "$OUT/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16", "filename" : "icon-16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16", "filename" : "icon-32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32", "filename" : "icon-32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32", "filename" : "icon-64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon-128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon-256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon-256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon-512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon-512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon-1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
printf '{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' > "$OUT/../Contents.json"
rm -rf "$TMP"
echo "$OUT"
