#!/bin/sh
# Builds, signs and notarizes a release, then writes the zip and the cask's
# sha256. Prepared, not yet run: it needs a Developer ID identity, a team,
# the App Group, and a notarytool keychain profile.
#
#   TEAM_ID=XXXXXXXXXX APP_GROUP=XXXXXXXXXX.io.github.whitenwhiten.topophany-bar \
#   NOTARY_PROFILE=topophany-bar VERSION=0.1.0 scripts/release.sh
#
# Set NOTARIZE=0 to stop after signing.
set -eu
: "${TEAM_ID:?set TEAM_ID}" "${APP_GROUP:?set APP_GROUP}" "${VERSION:?set VERSION}"
NOTARIZE="${NOTARIZE:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT"
xcodegen generate
rm -rf "$OUT" && mkdir -p "$OUT"
xcodebuild -project topophany-bar.xcodeproj -scheme topophany-bar -configuration Release \
  -archivePath "$OUT/topophany-bar.xcarchive" archive \
  MARKETING_VERSION="$VERSION" DEVELOPMENT_TEAM="$TEAM_ID" TOPOPHANY_APP_GROUP="$APP_GROUP" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" OTHER_CODE_SIGN_FLAGS="--timestamp"
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
