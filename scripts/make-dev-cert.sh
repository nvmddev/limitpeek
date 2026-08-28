#!/bin/bash
#
# Creates a self-signed code-signing identity for local development, so macOS
# stops re-asking for the app's Keychain item on every rebuild.
#
#   ./scripts/make-dev-cert.sh
#   export CODESIGN_IDENTITY="LimitPeek Dev"
#
# To undo: delete the "LimitPeek Dev" certificate in Keychain Access.
#
set -euo pipefail

CERT_NAME="${1:-LimitPeek Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
	echo "Identity '$CERT_NAME' already exists and is valid for code signing."
	echo "Use it with:  export CODESIGN_IDENTITY=\"$CERT_NAME\""
	exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> generating self-signed code-signing certificate"
openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
	-days 3650 -nodes -subj "/CN=$CERT_NAME" \
	-addext "basicConstraints=critical,CA:false" \
	-addext "keyUsage=critical,digitalSignature" \
	-addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# Apple's Security framework cannot read OpenSSL 3's default PKCS#12
# encryption, hence the legacy algorithms.
openssl pkcs12 -export -out "$WORK/cert.p12" \
	-inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$CERT_NAME" \
	-passout pass:temp \
	-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

echo "==> importing into the login keychain"
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P temp -T /usr/bin/codesign >/dev/null

echo "==> trusting it for code signing (macOS may ask for your password)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
	echo
	echo "Done. Now run:"
	echo "    export CODESIGN_IDENTITY=\"$CERT_NAME\""
	echo "    ./build.sh"
else
	echo "Certificate was created but is not showing as a valid signing identity." >&2
	exit 1
fi
