#!/bin/bash
#
# Renders the README pictures into docs/ from scripts/ReadmeArt.swift. Run it
# after changing the menu bar label, the menu or the icon, and commit what it
# writes. The menu is captured on screen, so the terminal needs Screen
# Recording permission, and it flashes up briefly per appearance.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && ! -x "$(xcode-select -p 2>/dev/null)/usr/bin/swiftc" ]]; then
	for candidate in /Applications/Xcode*.app/Contents/Developer; do
		if [[ -d "$candidate" ]]; then export DEVELOPER_DIR="$candidate"; break; fi
	done
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Only main.swift may hold top-level code, and LimitPeekApp.swift owns @main.
cp scripts/ReadmeArt.swift "$WORK/main.swift"
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done \
	< <(find Sources/LimitPeek -name '*.swift' ! -name 'LimitPeekApp.swift')

echo "==> compiling the renderer"
xcrun swiftc -DDEBUG -swift-version 6 -O \
	"${SOURCES[@]}" "$WORK/main.swift" -o "$WORK/readme-art"

OUT="${1:-docs}"
echo "==> rendering ${OUT}/"
"$WORK/readme-art" "$OUT"

swift scripts/IconRenderer.swift 256 "$OUT/icon.png"
echo "  ${OUT}/icon.png"
