#!/usr/bin/env bash
# Creates a self-signed "CoolMenu Dev" code-signing identity in the login keychain.
# Signing with a stable identity keeps macOS privacy grants (Accessibility) across rebuilds;
# ad-hoc signatures change every build, so the grant would silently stop applying.
set -euo pipefail

name="CoolMenu Dev"
if security find-identity -p codesigning | grep -q "\"$name\""; then
  echo "\"$name\" already exists"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cert.cnf" 2>/dev/null
# Throwaway passphrase: the p12 only exists for the import and is deleted on exit.
/usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -out "$tmp/cert.p12" -passout pass:coolmenu 2>/dev/null
security import "$tmp/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P coolmenu -T /usr/bin/codesign >/dev/null

echo "Created \"$name\". Rebuild with scripts/build-app.sh, then re-grant Accessibility once."
