#!/bin/sh
# Builds, signs and notarizes a release, then writes the disk image and the
# cask's sha256. It needs a Developer ID Application
# identity for the project's team (TOPOPHANY_TEAM in project.yml) and a
# notarytool keychain profile.
#
#   NOTARY_PROFILE=topophany-bar VERSION=0.1.0 scripts/release.sh
#
# The app is notarized and stapled before it goes in the image, so a copy
# dragged out of it opens offline; then the image is signed with the same
# certificate, notarized and stapled. Set NOTARIZE=0 to stop after signing.
# Extra arguments are passed to xcodebuild. NOTARY_KEYCHAIN optionally selects
# the keychain containing NOTARY_PROFILE (used by GitHub Actions).
set -eu
: "${VERSION:?set VERSION}"
NOTARIZE="${NOTARIZE:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${RELEASE_DIR:-$ROOT/build/release}"
CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then CHECK_ONLY=1; shift; fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT"
notarize() {
  if [ -n "${NOTARY_KEYCHAIN:-}" ]; then
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --keychain "$NOTARY_KEYCHAIN" --wait
  else
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  fi
}
for tool in xcodegen xcodebuild codesign xcrun security; do
  command -v "$tool" >/dev/null || { echo "missing release tool: $tool" >&2; exit 1; }
done
security find-identity -v -p codesigning | grep -q 'Developer ID Application:' || {
  echo "a valid Developer ID Application signing identity is required" >&2; exit 1;
}
if [ "$NOTARIZE" = 1 ]; then
  : "${NOTARY_PROFILE:?set NOTARY_PROFILE (xcrun notarytool store-credentials)}"
  if [ -n "${NOTARY_KEYCHAIN:-}" ]; then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --keychain "$NOTARY_KEYCHAIN" --output-format json >/dev/null
  else
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null
  fi
fi
if [ "$CHECK_ONLY" = 1 ]; then echo "release tools, signing identity and requested notarization profile verified"; exit 0; fi
[ ! -e "$OUT" ] || { echo "release output already exists; choose a new RELEASE_DIR to preserve prior artifacts" >&2; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "commit the reviewed source before building a release" >&2; exit 1; }
[ -z "$(git ls-files --others --exclude-standard)" ] || { echo "review untracked files before building a release" >&2; exit 1; }
xcodegen generate
mkdir -p "$OUT"
xcodebuild -project topophany-bar.xcodeproj -scheme topophany-bar -configuration Release \
  -archivePath "$OUT/topophany-bar.xcarchive" archive \
  MARKETING_VERSION="$VERSION" TOPOPHANY_SIGN=YES TOPOPHANY_IDENTITY_YES="Developer ID Application" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" "$@"
APP="$OUT/topophany-bar.xcarchive/Products/Applications/topophany-bar.app"
DMG="$OUT/topophany-bar-$VERSION.dmg"
codesign --verify --deep --strict --verbose=2 "$APP"
IDENTITY="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p')"
[ -n "$IDENTITY" ] || { echo "the app isn't signed with Developer ID" >&2; exit 1; }
if [ "$NOTARIZE" = 1 ]; then
  : "${NOTARY_PROFILE:?set NOTARY_PROFILE (xcrun notarytool store-credentials)}"
  ditto -c -k --keepParent "$APP" "$OUT/topophany-bar.zip"
  notarize "$OUT/topophany-bar.zip"
  rm "$OUT/topophany-bar.zip"
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose "$APP"
fi
SIGN="$IDENTITY" scripts/make-dmg.sh "$APP" "$DMG" "topophany-bar $VERSION"
if [ "$NOTARIZE" = 1 ]; then
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi
shasum -a 256 "$DMG" | awk '{print $1}' > "$OUT/sha256.txt"
python3 - "$OUT" "$VERSION" "$NOTARIZE" "$(git rev-parse HEAD)" <<'PYRECEIPT'
import json, pathlib, sys
out, version, notarized, revision = sys.argv[1:]
p = pathlib.Path(out)
(p / "release.json").write_text(json.dumps({"schema": 1, "version": version,
    "source_revision": revision, "notarized": notarized == "1",
    "sha256": (p / "sha256.txt").read_text().strip()}, indent=2) + "\n")
PYRECEIPT
echo "dmg:    $DMG"
echo "sha256: $(cat "$OUT/sha256.txt")"
