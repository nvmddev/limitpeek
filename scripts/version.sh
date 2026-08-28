#!/bin/bash
#
# Semantic version helper driven by git tags and Conventional Commits.
#
#   version.sh latest                 newest release tag, empty if none
#   version.sh previous <tag>         the tag released before <tag>
#   version.sh next [auto|patch|minor|major]
#                                     next version, without the "v"
#   version.sh app-changed [tag]      exit 0 if the built app would differ
#
# "auto" reads the commits since the newest tag: a `!` marker or a BREAKING
# CHANGE trailer means major, any feat: means minor, otherwise patch.
set -euo pipefail
cd "$(dirname "$0")/.."

# Paths whose contents end up in the shipped bundle.
APP_PATHS=(Sources Resources Package.swift)

all_tags() {
	git tag --list 'v[0-9]*' --sort=-v:refname
}

latest_tag() {
	local tags
	tags="$(all_tags)"
	printf '%s' "${tags%%$'\n'*}"
}

previous_tag() {
	local exclude="$1" tag prev
	# The tag <exclude> actually follows, so a higher version on a side branch
	# doesn't win. Falls through when <exclude> is not a commit yet.
	if prev="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "${exclude}^" 2>/dev/null)"; then
		printf '%s' "$prev"
		return 0
	fi
	while IFS= read -r tag; do
		[[ -z "$tag" || "$tag" == "$exclude" ]] && continue
		printf '%s' "$tag"
		return 0
	done <<< "$(all_tags)"
}

detect_bump() {
	local range="$1" bump="patch" record subject body
	while IFS= read -r -d $'\x1e' record; do
		record="${record#$'\n'}"
		subject="${record%%$'\x1f'*}"
		body="${record#*$'\x1f'}"
		if [[ "$subject" =~ ^[a-zA-Z]+(\([^\)]*\))?! ]] || [[ "$body" == *"BREAKING CHANGE"* ]]; then
			printf 'major'
			return 0
		fi
		[[ "$subject" =~ ^feat(\([^\)]*\))?: ]] && bump="minor"
	done < <(git log --no-merges --format='%s%x1f%b%x1e' "$range")
	printf '%s' "$bump"
}

case "${1:-}" in
latest)
	latest_tag
	echo
	;;
previous)
	[[ -n "${2:-}" ]] || { echo "usage: version.sh previous <tag>" >&2; exit 2; }
	previous_tag "$2"
	echo
	;;
app-changed)
	tag="${2:-$(latest_tag)}"
	if [[ -z "$tag" ]]; then
		echo "changed (no release tag yet)"
		exit 0
	fi
	# git diff --quiet exits 1 when there are differences, hence the inversion.
	if git diff --quiet "$tag" HEAD -- "${APP_PATHS[@]}"; then
		echo "unchanged since $tag"
		exit 1
	fi
	echo "changed since $tag"
	;;
next)
	bump="${2:-auto}"
	tag="$(latest_tag)"
	if [[ -z "$tag" ]]; then
		echo "0.1.0"
		exit 0
	fi

	current="${tag#v}"
	if [[ ! "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
		echo "error: newest tag '$tag' is not MAJOR.MINOR.PATCH" >&2
		exit 1
	fi
	major="${BASH_REMATCH[1]}"
	minor="${BASH_REMATCH[2]}"
	patch="${BASH_REMATCH[3]}"

	[[ "$bump" == "auto" ]] && bump="$(detect_bump "$tag..HEAD")"

	case "$bump" in
	major) major=$((major + 1)); minor=0; patch=0 ;;
	minor) minor=$((minor + 1)); patch=0 ;;
	patch) patch=$((patch + 1)) ;;
	*) echo "error: unknown bump '$bump'" >&2; exit 2 ;;
	esac
	echo "${major}.${minor}.${patch}"
	;;
*)
	echo "usage: version.sh {latest|previous <tag>|next [auto|patch|minor|major]|app-changed [tag]}" >&2
	exit 2
	;;
esac
