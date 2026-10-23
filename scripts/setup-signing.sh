#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/build/signing"
KEYCHAIN="$DIR/dev.keychain"
PASSWORD_FILE="$DIR/.password"
IDENTITY="${SIGN_IDENTITY:-New Window Plz Development}"

mkdir -p "$DIR"
if [[ -f "$KEYCHAIN" ]]; then
  echo "Signing keychain already exists: $KEYCHAIN"
  exit 0
fi

PASS="$(openssl rand -hex 24)"
printf '%s' "$PASS" > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

cat > "$DIR/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
O = New Window Plz
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
CNF

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$DIR/key.pem" -out "$DIR/cert.pem" -days 3650 \
  -config "$DIR/openssl.cnf" >/dev/null 2>&1
openssl pkcs12 -export -legacy -macalg sha1 \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
  -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -name "$IDENTITY" \
  -out "$DIR/identity.p12" -passout "pass:$PASS" >/dev/null 2>&1

security create-keychain -p "$PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$PASS" "$KEYCHAIN"
security import "$DIR/identity.p12" -k "$KEYCHAIN" -P "$PASS" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$PASS" "$KEYCHAIN" >/dev/null

rm -f "$DIR/key.pem" "$DIR/identity.p12"
echo "Created $KEYCHAIN"
echo "Identity: $IDENTITY"
echo "This keychain is intentionally local and gitignored. Back it up if you"
echo "want the same Accessibility grant to survive a machine migration."
