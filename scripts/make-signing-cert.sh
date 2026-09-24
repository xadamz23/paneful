#!/bin/bash
# One-time: creates a self-signed "Paneful Dev" code-signing identity in your login keychain,
# so Paneful's signature, and with it the Accessibility permission, stays the same across rebuilds.
set -euo pipefail
NAME="Paneful Dev"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
  echo "'$NAME' already exists."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem"

# macOS's `security import` can't read OpenSSL 3's default PKCS#12 encryption.
LEGACY=""
if openssl version | grep -q '^OpenSSL 3'; then LEGACY="-legacy"; fi
openssl pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:paneful

security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P paneful -T /usr/bin/codesign
echo "Created '$NAME'."
