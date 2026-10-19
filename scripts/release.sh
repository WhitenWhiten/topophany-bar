#!/bin/sh
# Builds, signs and notarizes a release, then writes the zip and the cask's
# sha256. Prepared, not yet run: it needs a Developer ID Application
# identity for the project's team (TOPOPHANY_TEAM in project.yml) and a
# notarytool keychain profile.
#
#   NOTARY_PROFILE=topophany-bar VERSION=0.1.0 scripts/release.sh
#
# Set NOTARIZE=0 to stop after signing.
set -eu
: "${VERSION:?set VERSION}"
NOTARIZE="${NOTARIZE:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT"
xcodegen generate
rm -rf "$OUT" && mkdir -p "$OUT"
xcodebuild -project topophany-bar.xcodeproj -scheme topophany-bar -configuration Release \
  -archivePath "$OUT/topophany-bar.xcarchive" archive \
  MARKETING_VERSION="$VERSION" TOPOPHANY_SIGN=YES TOPOPHANY_IDENTITY_YES="Developer ID Application" \
  OTHER_CODE_SIGN_FLAGS="--timestamp"
APP="$OUT/topophany-bar.xcarchive/Products/Applications/topophany-bar.app"
codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --keepParent "$APP" "$OUT/topophany-bar-$VERSION.zip"
if [ "$NOTARIZE" = 1 ]; then
  : "${NOTARY_PROFILE:?set NOTARY_PROFILE (xcrun notarytool store-credentials)}"
  xcrun notarytool submit "$OUT/topophany-bar-$VERSION.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm "$OUT/topophany-bar-$VERSION.zip"
  ditto -c -k --keepParent "$APP" "$OUT/topophany-bar-$VERSION.zip"
  spctl --assess --type execute --verbose "$APP"
fi
shasum -a 256 "$OUT/topophany-bar-$VERSION.zip" | awk '{print $1}' > "$OUT/sha256.txt"
echo "zip:    $OUT/topophany-bar-$VERSION.zip"
echo "sha256: $(cat "$OUT/sha256.txt")"
