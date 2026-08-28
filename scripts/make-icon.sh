#!/bin/bash
#
# Renders Resources/AppIcon.icns from scripts/IconRenderer.swift.
#
#   scripts/make-icon.sh [compile]   re-render and record the source hash
#   scripts/make-icon.sh verify      check the hash without rendering
#
# The .icns is committed, so `verify` is what catches artwork that was edited
# but never recompiled. CI runs it.
set -euo pipefail
cd "$(dirname "$0")/.."

RENDERER="scripts/IconRenderer.swift"
ICNS="Resources/AppIcon.icns"
CHECKSUM_FILE="Resources/AppIcon.sha256"
MODE="${1:-compile}"

source_checksum() {
	shasum -a 256 "$RENDERER" | cut -d' ' -f1
}

if [[ "$MODE" == "verify" ]]; then
	[[ -f "$ICNS" ]] || { echo "error: $ICNS is missing — run scripts/make-icon.sh" >&2; exit 1; }
	[[ -f "$CHECKSUM_FILE" ]] || { echo "error: $CHECKSUM_FILE is missing" >&2; exit 1; }
	if [[ "$(source_checksum)" != "$(cat "$CHECKSUM_FILE")" ]]; then
		echo "error: $RENDERER changed since $ICNS was built — run scripts/make-icon.sh" >&2
		exit 1
	fi
	echo "icon artifacts are current"
	exit 0
fi

[[ "$MODE" == "compile" ]] || { echo "usage: make-icon.sh [compile|verify]" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
            "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
            "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
	swift "$RENDERER" "${spec%%:*}" "$ICONSET/${spec##*:}.png"
done

iconutil -c icns "$ICONSET" -o "$ICNS"
source_checksum > "$CHECKSUM_FILE"
echo "built $ICNS ($(du -h "$ICNS" | cut -f1))"
