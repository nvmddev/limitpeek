#!/bin/bash
#
# Builds build/LimitPeek.app from the SwiftPM package.
#
#   ./build.sh            release, universal
#   ./build.sh --debug    debug, host arch only
#   ./build.sh --run      build, then relaunch
#
# The signing identity is picked automatically: a Developer ID Application
# certificate, then the "LimitPeek Dev" cert from scripts/make-dev-cert.sh, then
# ad-hoc. CODESIGN_IDENTITY overrides. See docs/signing.md.
set -euo pipefail

cd "$(dirname "$0")"

# Universal builds and swift-testing need the full Xcode toolchain.
if [[ -z "${DEVELOPER_DIR:-}" && ! -x "$(xcode-select -p 2>/dev/null)/usr/bin/xcodebuild" ]]; then
	for candidate in /Applications/Xcode*.app/Contents/Developer; do
		if [[ -d "$candidate" ]]; then export DEVELOPER_DIR="$candidate"; break; fi
	done
fi

APP_NAME="LimitPeek"
BUNDLE_ID="${BUNDLE_ID:-dev.nevermind.LimitPeek}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

# Ad-hoc signatures change on every build, which invalidates the Keychain ACL
# and makes macOS re-ask for the app's own token. Prefer a stable identity.
if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
	IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
	DEV_ID="$(printf '%s\n' "$IDENTITIES" \
		| sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p' | head -1)"
	if [[ -n "$DEV_ID" ]]; then
		CODESIGN_IDENTITY="$DEV_ID"
	elif printf '%s\n' "$IDENTITIES" | grep -q "LimitPeek Dev"; then
		CODESIGN_IDENTITY="LimitPeek Dev"
	else
		CODESIGN_IDENTITY="-"
	fi
fi

# "Developer ID Application: Name (ABCDE12345)" already carries the Team ID.
if [[ -z "${TEAM_ID:-}" && "$CODESIGN_IDENTITY" == "Developer ID Application:"* ]]; then
	TEAM_ID="$(printf '%s' "$CODESIGN_IDENTITY" | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p')"
fi

CONFIGURATION="release"
UNIVERSAL=1
RUN_AFTER=0

for arg in "$@"; do
	case "$arg" in
		--debug) CONFIGURATION="debug"; UNIVERSAL=0 ;;
		--run)   RUN_AFTER=1 ;;
		*) echo "unknown option: $arg" >&2; exit 2 ;;
	esac
done

BUILD_FLAGS=(-c "$CONFIGURATION")
if [[ $UNIVERSAL -eq 1 ]]; then
	BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi

echo "==> swift build ${BUILD_FLAGS[*]}"
if ! swift build "${BUILD_FLAGS[@]}"; then
	if [[ $UNIVERSAL -eq 1 ]]; then
		echo "    universal build failed; falling back to host architecture only" >&2
		BUILD_FLAGS=(-c "$CONFIGURATION")
		swift build "${BUILD_FLAGS[@]}"
	else
		exit 1
	fi
fi

BIN_PATH="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
APP="build/${APP_NAME}.app"

echo "==> assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# SwiftPM emits resources as a side-by-side .bundle. Copy the app target's own
# and nothing else -- a plain glob picks up the test bundle and ships the
# fixtures inside the app.
APP_BUNDLE="$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$APP_BUNDLE" ]]; then
	cp -R "$APP_BUNDLE" "$APP/Contents/Resources/"
fi

# A keychain-access-group lets the app own its Keychain items outright, which
# silences the last permission prompt. It is a restricted entitlement: without a
# provisioning profile authorising it, AMFI kills the app at launch. So it goes
# in only when both the profile and a Team ID are present. See docs/signing.md.
PROFILE_PATH="${PROVISION_PROFILE:-Resources/embedded.provisionprofile}"
ENTITLEMENTS="Resources/${APP_NAME}.entitlements"
if [[ -n "${TEAM_ID:-}" && -f "$PROFILE_PATH" ]]; then
	cp "$PROFILE_PATH" "$APP/Contents/embedded.provisionprofile"
	ENTITLEMENTS="build/${APP_NAME}.generated.entitlements"
	cp "Resources/${APP_NAME}.entitlements" "$ENTITLEMENTS"
	/usr/libexec/PlistBuddy \
		-c "Add :keychain-access-groups array" \
		-c "Add :keychain-access-groups:0 string ${TEAM_ID}.${BUNDLE_ID}" \
		"$ENTITLEMENTS" >/dev/null
	echo "==> embedding provisioning profile; keychain-access-group ${TEAM_ID}.${BUNDLE_ID}"
elif [[ -n "${TEAM_ID:-}" ]]; then
	echo "==> no ${PROFILE_PATH} -- skipping keychain-access-groups"
fi

sed -e "s|__BUNDLE_ID__|${BUNDLE_ID}|g" \
    -e "s|__VERSION__|${VERSION}|g" \
    -e "s|__BUILD__|${BUILD_NUMBER}|g" \
    Resources/Info.plist > "$APP/Contents/Info.plist"

printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -f Resources/AppIcon.icns ]]; then
	cp Resources/AppIcon.icns "$APP/Contents/Resources/"
	/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
fi

# Notarisation needs a secure timestamp, which ad-hoc and self-signed
# identities cannot get -- no trusted chain to Apple's TSA.
TIMESTAMP="--timestamp=none"
if [[ "$CODESIGN_IDENTITY" == "Developer ID Application:"* ]]; then
	TIMESTAMP="--timestamp"
fi

echo "==> codesign (identity: ${CODESIGN_IDENTITY})"
codesign --force \
         --sign "$CODESIGN_IDENTITY" \
         --entitlements "$ENTITLEMENTS" \
         --options runtime \
         "$TIMESTAMP" \
         "$APP"

codesign --verify --deep --strict "$APP"

echo "==> ok: ${APP}"
du -sh "$APP" | sed 's/^/    size: /'

if [[ $RUN_AFTER -eq 1 ]]; then
	echo "==> relaunching"
	pkill -x "$APP_NAME" 2>/dev/null || true
	open "$APP"
fi
