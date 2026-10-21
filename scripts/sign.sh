#!/bin/bash
# Signs an app bundle with a stable self-signed identity so macOS keeps the Accessibility
# permission across rebuilds (the designated requirement pins the certificate, not the binary hash).
# Usage: scripts/sign.sh build/Rambla.app
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$1"
IDENTITY="Rambla Local Signing"
DIR="$PWD/.signing"
KC="$DIR/rambla-signing.keychain-db"
PASS="scroll"

create_identity() {
  mkdir -p "$DIR"
  local tmp; tmp=$(mktemp -d)
  cat > "$tmp/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $IDENTITY
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -days 3650 -config "$tmp/cert.cnf" >/dev/null 2>&1
  # macOS `security` cannot read modern PKCS#12 encryption; -legacy keeps it compatible (Homebrew OpenSSL 3).
  openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout pass:$PASS -name "$IDENTITY" >/dev/null 2>&1 \
    || /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout pass:$PASS -name "$IDENTITY"
  security create-keychain -p "$PASS" "$KC"
  security set-keychain-settings "$KC"   # no auto-lock
  security unlock-keychain -p "$PASS" "$KC"
  security import "$tmp/id.p12" -k "$KC" -P "$PASS" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null
  rm -rf "$tmp"
  echo "Created signing identity '$IDENTITY' in $KC"
}

adhoc() {
  echo "warning: falling back to ad-hoc signing (Accessibility permission will reset on each update)" >&2
  codesign --force --sign - "$APP"
}

[ -f "$KC" ] || create_identity || { adhoc; exit 0; }
security unlock-keychain -p "$PASS" "$KC"

ORIGINAL=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"; line="${line%\"}"; line="${line#\"}"
  [ -n "$line" ] && ORIGINAL+=("$line")
done < <(security list-keychains -d user)
restore() { security list-keychains -d user -s "${ORIGINAL[@]}"; }
trap restore EXIT
security list-keychains -d user -s "${ORIGINAL[@]}" "$KC"

codesign --force --keychain "$KC" --sign "$IDENTITY" "$APP" || { restore; trap - EXIT; adhoc; exit 0; }
