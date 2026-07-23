#!/bin/bash
#
# Create a self-signed "SpacePill Dev" code signing certificate.
#
# WHY YOU WANT THIS
#   SpacePill needs Accessibility and Input Monitoring permission. macOS keys
#   those grants to the app's code signature. An ad-hoc signature (`codesign -s -`)
#   gets a fresh cdhash on every build, so macOS sees each rebuild as a brand new
#   app and silently drops both grants -- the hotkeys and the space-change event
#   tap stop working until you re-approve them in System Settings.
#
#   Signing with a stable certificate instead means you approve once, ever.
#
# USAGE
#   ./bin/dev-cert.sh
#
#   Requires unlocking your login keychain, so run it yourself in a terminal;
#   it cannot be run unattended. Afterwards bin/start.sh picks the identity up
#   automatically. Run it once per machine.
#
# TO UNDO
#   security delete-identity -c "SpacePill Dev" ~/Library/Keychains/login.keychain-db

set -euo pipefail

CN="SpacePill Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

if security find-identity -v -p codesigning | grep -q "$CN"; then
    echo "✅ '$CN' identity already exists. Nothing to do."
    exit 0
fi

echo "🔑 Unlocking login keychain (your macOS login password)..."
security unlock-keychain "$KEYCHAIN"

echo "📜 Generating self-signed code signing certificate..."
cat > "$WORKDIR/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $CN
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
    -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
    -config "$WORKDIR/cert.cnf" 2>/dev/null

# macOS Security.framework cannot read OpenSSL 3's default PKCS#12 encryption,
# so force the legacy algorithms it does understand.
openssl pkcs12 -export -out "$WORKDIR/dev.p12" \
    -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
    -passout pass:spacepill \
    -legacy -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

echo "📥 Importing into login keychain..."
security import "$WORKDIR/dev.p12" -k "$KEYCHAIN" -P spacepill \
    -T /usr/bin/codesign -T /usr/bin/security

# Let codesign use the key without prompting for keychain access every build.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 \
    || echo "⚠️  Could not set the key partition list; codesign may prompt on first use."

# Trust the certificate for code signing. Needs admin rights.
echo "🔏 Marking the certificate as trusted for code signing (needs sudo)..."
sudo security add-trusted-cert -d -r trustRoot \
    -p codeSign -k /Library/Keychains/System.keychain "$WORKDIR/cert.pem"

echo
if security find-identity -v -p codesigning | grep -q "$CN"; then
    echo "✅ Done. './bin/start.sh' will now sign with '$CN'."
    echo "   Grant Accessibility + Input Monitoring once and the grants will stick."
else
    echo "❌ The identity did not appear. Check the output above."
    exit 1
fi
