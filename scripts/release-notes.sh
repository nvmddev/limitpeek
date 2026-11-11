#!/bin/bash
#
# Prints the body for a GitHub release: what changed first, then how to
# install or update. `brew install` also upgrades an outdated cask.
#
#   release-notes.sh <version> [previous] [ref]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release-notes.sh <version> [previous] [ref]}"
PREVIOUS="${2:-}"
REF="${3:-HEAD}"
REPO="${GITHUB_REPOSITORY:-nvmddev/limitpeek}"
NOTARIZED="${NOTARIZED:-true}"

# Without the version heading, and with the groups raised to the level of
# the install section.
scripts/changelog.sh section "$VERSION" "$PREVIOUS" "$REF" \
	| tail -n +2 | sed -e '/./,$!d' -e 's/^### /## /'

if [[ -n "$PREVIOUS" ]]; then
	printf '\n**Full diff:** https://github.com/%s/compare/%s...v%s\n' "$REPO" "$PREVIOUS" "$VERSION"
fi

cat <<MD

## Install or update

\`\`\`sh
brew install --cask nvmddev/tap/limitpeek
\`\`\`

Or download \`LimitPeek-${VERSION}.dmg\` below and drag **LimitPeek.app** into
\`/Applications\`. To update, quit LimitPeek first and open it again afterwards.
Apple silicon, macOS 14 or newer.
MD

if [[ "$NOTARIZED" != "true" ]]; then
	cat <<'MD'

> This build is ad-hoc signed rather than notarized, so macOS quarantines it on
> first launch. Right-click the app → **Open** → **Open**, or run
> `xattr -dr com.apple.quarantine /Applications/LimitPeek.app`.
MD
fi

cat <<'MD'

---

LimitPeek is an unofficial project and is not affiliated with Anthropic.
MD
