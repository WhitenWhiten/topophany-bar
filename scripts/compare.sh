#!/bin/sh
# Puts a preview render and an app snapshot side by side, at the same scale.
# Usage: scripts/compare.sh "one.html?QUERY" SNAPSHOT.png OUT.png [TITLE]
# Both are 2x; the page shows them at 1x points and is shot at 2x.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
CH="$HOME/Library/Caches/ms-playwright/chromium_headless_shell-1248/chrome-headless-shell-mac-arm64/chrome-headless-shell"
# shot.sh's virtual time stalls while the display sleeps; plain headless
# shots wait for the page's load event, which is enough here.
"$CH" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --run-all-compositor-stages-before-draw \
  --window-size=1600,2400 --screenshot="$TMP/preview.png" "file://$ROOT/design/shots/$1" >/dev/null 2>&1
# Trim the transparent/white margin chrome leaves around the stage.
W=$(sips -g pixelWidth "$2" | awk '/pixelWidth/{print $2}')
cat > "$TMP/c.html" <<HTML
<!doctype html><meta charset="utf-8"><style>
body{margin:0;background:#16171a;font:600 13px -apple-system,system-ui;color:#c9ccd2}
.row{display:flex;gap:28px;padding:20px;align-items:flex-start}
figure{margin:0} figcaption{margin:0 0 8px 2px} img{display:block}

</style>
<div class="row">
<figure><figcaption>Preview · ${4:-}</figcaption><div id="pw" style="overflow:hidden"><img id="p" src="preview.png"></div></figure>
<figure><figcaption>App snapshot</figcaption><img id="s" src="snap.png"></figure>
</div>
<script>
const p=document.getElementById('p'), s=document.getElementById('s');
function fit(){ if(!p.naturalWidth||!s.naturalWidth) return;
 // the stage is the top-left of the preview shot; find its extent by scanning
 const c=document.createElement('canvas'); c.width=p.naturalWidth; c.height=p.naturalHeight;
 const x=c.getContext('2d'); x.drawImage(p,0,0); const d=x.getImageData(0,0,c.width,c.height).data;
 let mw=0,mh=0; for(let y=0;y<c.height;y+=2) for(let i=0;i<c.width;i+=2){const k=(y*c.width+i)*4; if(d[k+3]>0 && !(d[k]>250&&d[k+1]>250&&d[k+2]>250)){ if(i>mw)mw=i; if(y>mh)mh=y; }}
 p.style.width=(c.width/2)+'px'; document.getElementById('pw').style.width=((mw+2)/2)+'px'; document.getElementById('pw').style.height=((mh+2)/2)+'px';
 s.style.width=(s.naturalWidth/2)+'px'; }
p.onload=fit; s.onload=fit;
</script>
HTML
cp "$2" "$TMP/snap.png"
"$CH" --headless --disable-gpu --hide-scrollbars --allow-file-access-from-files --force-device-scale-factor=1 --run-all-compositor-stages-before-draw \
  --window-size="$(( W > 1200 ? W + 140 : 1300 ))",2200 --screenshot="$3" "file://$TMP/c.html" >/dev/null 2>&1
echo "$3"
