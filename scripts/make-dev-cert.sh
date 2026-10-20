#!/bin/bash
# Creates a self-signed code-signing identity "BA-KEY Menu Dev" in the login keychain.
# build-app.sh uses it automatically, so macOS keeps the app's Input Monitoring permission
# across rebuilds. Remove it any time in Keychain Access (search "BA-KEY Menu Dev").
set -euo pipefail
NAME="BA-KEY Menu Dev"
if security find-identity -p codesigning | grep -q "\"$NAME\""; then echo "Already exists."; exit 0; fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cs.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -config "$TMP/cs.cnf"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -out "$TMP/id.p12" -passout pass:tmp
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P tmp -T /usr/bin/codesign
echo "Created code-signing identity '$NAME'."
