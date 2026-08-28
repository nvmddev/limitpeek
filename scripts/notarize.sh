#!/bin/bash
#
# Submits an artifact to Apple's notary service and waits for the verdict.
#
#   scripts/notarize.sh <file> [--staple]
#
# Credentials come from APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD (an
# app-specific password from appleid.apple.com, not the account password), or
# from a stored keychain profile named by NOTARY_PROFILE:
#
#   xcrun notarytool store-credentials limitpeek-notary \
#         --apple-id you@example.com --team-id ABCDE12345
#
# A .zip can be submitted but not stapled — the ticket goes onto the .app inside
# it, so callers notarize the zip, staple the app, then re-zip. A .dmg is both
# submitted and stapled, hence the flag.
set -euo pipefail
cd "$(dirname "$0")/.."

FILE="${1:-}"
STAPLE="${2:-}"
[[ -n "$FILE" && -e "$FILE" ]] || { echo "usage: notarize.sh <file> [--staple]" >&2; exit 2; }

CREDENTIALS=()
if [[ -n "${APPLE_ID:-}" ]]; then
	: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required alongside APPLE_ID}"
	: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required alongside APPLE_ID}"
	CREDENTIALS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
else
	CREDENTIALS=(--keychain-profile "${NOTARY_PROFILE:-limitpeek-notary}")
fi

# Apple rejects anything not signed by a Developer ID with a secure timestamp.
# Checking here turns a slow round trip into an instant failure.
if [[ "$FILE" == *.app ]]; then
	SIGNATURE="$(codesign -dvv "$FILE" 2>&1 || true)"
	grep -q "Authority=Developer ID Application" <<<"$SIGNATURE" \
		|| { echo "$FILE is not signed with a Developer ID" >&2; exit 1; }
	grep -q "^Timestamp=" <<<"$SIGNATURE" \
		|| { echo "$FILE has no secure timestamp" >&2; exit 1; }
fi

echo "==> submitting $FILE (usually a few minutes)"
# Captured rather than streamed, so the submission id survives a rejection.
if output="$(xcrun notarytool submit "$FILE" "${CREDENTIALS[@]}" --wait --timeout 30m 2>&1)"; then
	printf '%s\n' "$output"
else
	printf '%s\n' "$output" >&2
	submission="$(printf '%s\n' "$output" | awk '/^ *id: /{print $2; exit}')"
	if [[ -n "$submission" ]]; then
		echo "==> fetching the notary log for $submission" >&2
		xcrun notarytool log "$submission" "${CREDENTIALS[@]}" >&2 || true
	fi
	exit 1
fi

if [[ "$STAPLE" == "--staple" ]]; then
	echo "==> stapling $FILE"
	xcrun stapler staple "$FILE"
	xcrun stapler validate "$FILE"
fi
