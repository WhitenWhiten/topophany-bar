#!/bin/sh
# Packs an app into a drag-to-install disk image: the app beside a link to
# Applications, on the window scripts/make-dmg-background.swift draws.
#
#   scripts/make-dmg.sh APP OUT.dmg [VOLUME]
#
# dmgbuild writes the window's layout itself, so nothing drives Finder. It is
# installed, pinned by hash, in build/dmgbuild-venv on first use. Set SIGN to
# a codesigning identity to sign the image as well.
set -eu
APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUT="$2"
VOLUME="${3:-topophany-bar}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$ROOT/build/dmgbuild-venv"
[ -d "$APP/Contents" ] || { echo "no app at $APP" >&2; exit 1; }
if [ ! -x "$VENV/bin/dmgbuild" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q --require-hashes -r "$ROOT/packaging/dmg/requirements.txt"
fi
WORK="$(mktemp -d)"
trap 'hdiutil detach -quiet "$WORK/mnt" 2>/dev/null || true; rm -rf "$WORK"' EXIT
"$VENV/bin/dmgbuild" -s "$ROOT/packaging/dmg/settings.py" \
  -D app="$APP" -D background="$ROOT/packaging/dmg/background.png" "$VOLUME" "$WORK/rw.dmg"
# dmgbuild leaves the background at .background.tiff. In a folder it hides
# behind Applications for those who show hidden files; a move keeps the
# file's ID, which the window's alias to it follows.
mkdir "$WORK/mnt"
hdiutil attach -quiet -nobrowse -noautoopen "$WORK/rw.dmg" -mountpoint "$WORK/mnt"
mkdir "$WORK/mnt/.background"
mv "$WORK/mnt/.background.tiff" "$WORK/mnt/.background/background.tiff"
rm -rf "$WORK/mnt/.fseventsd" "$WORK/mnt/.Trashes"
hdiutil detach -quiet "$WORK/mnt"
rm -f "$OUT"
hdiutil convert -quiet "$WORK/rw.dmg" -format ULMO -o "$OUT"
if [ -n "${SIGN:-}" ]; then
  codesign --sign "$SIGN" --timestamp "$OUT"
  codesign --verify --verbose=2 "$OUT"
fi
echo "dmg: $OUT"
