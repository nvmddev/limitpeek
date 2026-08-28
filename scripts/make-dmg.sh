#!/bin/bash
#
# Wraps build/LimitPeek.app in a drag-to-Applications disk image.
#
#   VERSION            names the image. Default: the app's own version.
#   CODESIGN_IDENTITY  identity for the image itself ("-" skips signing).
#
# No Finder window styling: that drives Finder over Apple Events and is
# unreliable on a headless runner. A plain image installs identically.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/LimitPeek.app"
[[ -d "$APP" ]] || { echo "error: $APP not found — run ./build.sh first" >&2; exit 1; }

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
IDENTITY="${CODESIGN_IDENTITY:--}"
OUT="dist/LimitPeek-${VERSION}.dmg"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

# ditto, not cp -R: it preserves the code signature and extended attributes.
ditto "$APP" "$STAGING/LimitPeek.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p dist
rm -f "$OUT"

echo "==> creating $OUT"
hdiutil create \
	-volname "LimitPeek ${VERSION}" \
	-srcfolder "$STAGING" \
	-fs HFS+ \
	-format UDZO \
	-ov -quiet \
	"$OUT"

if [[ "$IDENTITY" != "-" ]]; then
	echo "==> signing $OUT"
	codesign --force --timestamp --sign "$IDENTITY" "$OUT"
fi

echo "==> ok: $OUT"
