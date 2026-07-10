#!/bin/bash
# Creates a stable, self-signed code-signing identity in a dedicated keychain.
# Rebuilds then keep the same signature, so macOS remembers Klaxon's Calendar
# permission across rebuilds instead of re-prompting every time (ad-hoc
# signing changes the signature on every build, which is why it re-asks).
#
# Run once. build-app.sh picks up this identity automatically when present.
set -euo pipefail

IDENTITY="Klaxon Local Signing"
KC="klaxon-signing.keychain"
PASS="klaxon-local"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "Signing identity '$IDENTITY' already exists — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Klaxon Local Signing
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

# Use the system LibreSSL, not Homebrew OpenSSL 3.x: the latter writes PKCS12
# with a MAC/cipher that Apple's `security import` rejects.
OPENSSL="/usr/bin/openssl"
[ -x "$OPENSSL" ] || OPENSSL="openssl"

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" >/dev/null 2>&1
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:"$PASS" -name "$IDENTITY" >/dev/null 2>&1

# A dedicated keychain we fully control — no login-keychain password needed.
security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$PASS" "$KC"
security set-keychain-settings "$KC"               # never auto-lock
security unlock-keychain -p "$PASS" "$KC"
# Keep existing keychains searchable alongside the new one.
EXISTING=$(security list-keychains -d user | sed -e 's/"//g' -e 's/^[[:space:]]*//')
security list-keychains -d user -s "$KC" $EXISTING

security import "$TMP/id.p12" -k "$KC" -P "$PASS" -A -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null 2>&1 || true

echo "Created signing identity '$IDENTITY'."
echo "Now run ./Scripts/build-app.sh — the first rebuild re-prompts once, then"
echo "the Calendar permission sticks across future rebuilds."
