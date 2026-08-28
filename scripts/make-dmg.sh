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
RW="$(mktemp -u)".dmg
MOUNT="$(mktemp -d)"
cleanup() {
	hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true
	rm -rf "$STAGING" "$MOUNT" "$RW"
}
trap cleanup EXIT

# ditto, not cp -R: it preserves the code signature and extended attributes.
ditto "$APP" "$STAGING/LimitPeek.app"
ln -s /Applications "$STAGING/Applications"
cp Resources/AppIcon.icns "$STAGING/.VolumeIcon.icns"

mkdir -p dist
rm -f "$OUT"

echo "==> creating $OUT"
# Built read/write first: the custom-icon bit lives in the volume root's
# Finder info, which only exists once the image is mounted.
hdiutil create \
	-volname "LimitPeek ${VERSION}" \
	-srcfolder "$STAGING" \
	-fs HFS+ \
	-format UDRW \
	-ov -quiet \
	"$RW"

hdiutil attach "$RW" -mountpoint "$MOUNT" -nobrowse -noautoopen -quiet
SetFile -a C "$MOUNT"
hdiutil detach "$MOUNT" -quiet

hdiutil convert "$RW" -format UDZO -o "$OUT" -ov -quiet

if [[ "$IDENTITY" != "-" ]]; then
	echo "==> signing $OUT"
	codesign --force --timestamp --sign "$IDENTITY" "$OUT"
fi

echo "==> ok: $OUT"
