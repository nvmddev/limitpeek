#!/bin/bash
#
# Maintains CHANGELOG.md from Conventional Commits.
#
#   changelog.sh section <version> [previous] [ref]   print one release section
#   changelog.sh prepend <version> [previous] [ref]   insert it into CHANGELOG.md
#
# Commits that don't parse as Conventional Commits land under "Other", so
# nothing silently disappears from a release.
set -euo pipefail
cd "$(dirname "$0")/.."

FILE="CHANGELOG.md"
HEADER="# Changelog"

section() {
	local version="$1" previous="$2" ref="$3" range date
	range="$ref"
	[[ -n "$previous" ]] && range="${previous}..${ref}"
	date="$(git log -1 --format=%cs "$ref")"

	local feats=() fixes=() others=()
	while IFS= read -r subject; do
		case "$subject" in
		feat*:*) feats+=("${subject#*: }") ;;
		fix*:*)  fixes+=("${subject#*: }") ;;
		build*:*|chore*:*|ci*:*|docs*:*|refactor*:*|style*:*|test*:*) ;;
		*) others+=("$subject") ;;
		esac
	done < <(git log --no-merges --format='%s' "$range")

	printf '## %s — %s\n' "$version" "$date"
	print_group "Added" "${feats[@]+"${feats[@]}"}"
	print_group "Fixed" "${fixes[@]+"${fixes[@]}"}"
	print_group "Other" "${others[@]+"${others[@]}"}"

	if [[ ${#feats[@]} -eq 0 && ${#fixes[@]} -eq 0 && ${#others[@]} -eq 0 ]]; then
		printf '\nMaintenance only.\n'
	fi
}

print_group() {
	local title="$1"
	shift
	[[ $# -gt 0 ]] || return 0
	printf '\n### %s\n\n' "$title"
	printf -- '- %s\n' "$@"
}

MODE="${1:-}"
VERSION="${2:-}"
PREVIOUS="${3:-}"
REF="${4:-HEAD}"
[[ -n "$MODE" && -n "$VERSION" ]] || {
	echo "usage: changelog.sh {section|prepend} <version> [previous] [ref]" >&2
	exit 2
}

case "$MODE" in
section)
	section "$VERSION" "$PREVIOUS" "$REF"
	;;
prepend)
	NEW="$(section "$VERSION" "$PREVIOUS" "$REF")"
	if [[ -f "$FILE" ]] && grep -q "^## ${VERSION} " "$FILE"; then
		echo "$FILE already has a section for $VERSION"
		exit 0
	fi
	{
		printf '%s\n\n' "$HEADER"
		printf '%s\n' "$NEW"
		if [[ -f "$FILE" ]]; then
			printf '\n'
			tail -n +2 "$FILE" | sed '/./,$!d'
		fi
	} > "${FILE}.tmp"
	mv "${FILE}.tmp" "$FILE"
	echo "prepended $VERSION to $FILE"
	;;
*)
	echo "usage: changelog.sh {section|prepend} <version> [previous] [ref]" >&2
	exit 2
	;;
esac
