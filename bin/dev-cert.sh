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
#   ./bin/dev-cert.sh          create the identity (idempotent)
#   ./bin/dev-cert.sh --check  report on the existing identity and exit
#
#   Prompts for your login keychain password, so run it yourself in a terminal.
#   Works fine over SSH. Run it once per machine; afterwards bin/start.sh picks
#   the identity up automatically.
#
# TO UNDO
#   security delete-identity -c "SpacePill Dev" ~/Library/Keychains/login.keychain-db

set -euo pipefail

CN="SpacePill Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# Does an identity with this name exist at all? Note: `find-identity -v` lists
# only *trusted* identities, and a self-signed cert is never trusted, so
# checking with -v here would rebuild the cert on every run and pile up
# duplicates in the keychain.
identity_hash() {
    security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
        | awk -v cn="\"$CN\"" '$0 ~ cn {print $2; exit}'
}

# codesign refuses to use a key it cannot read, so proving the identity works
# means actually signing something with it.
test_sign() {
    local hash="$1"
    local probe="$WORKDIR/probe"
    cp /usr/bin/true "$probe"
    codesign --force --sign "$hash" "$probe" >/dev/null 2>&1
}

if [ "${1:-}" = "--check" ]; then
    HASH=$(identity_hash)
    if [ -z "$HASH" ]; then
        echo "❌ No '$CN' identity found. Run ./bin/dev-cert.sh"
        exit 1
    fi
    if test_sign "$HASH"; then
        echo "✅ '$CN' ($HASH) is present and can sign."
    else
        echo "⚠️  '$CN' exists but codesign cannot use its private key."
        echo "   Re-run ./bin/dev-cert.sh to repair the key partition list."
        exit 1
    fi
    exit 0
fi

# Ask once and reuse: unlock-keychain and set-key-partition-list both need it,
# and set-key-partition-list cannot fall back to an interactive prompt.
printf "🔑 Login keychain password: "
read -rs KEYCHAIN_PASSWORD
echo

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

HASH=$(identity_hash)

if [ -n "$HASH" ]; then
    echo "📎 Reusing existing '$CN' certificate ($HASH)."
else
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

    # macOS Security.framework cannot read OpenSSL 3's default PKCS#12
    # encryption, so force the legacy algorithms it does understand.
    openssl pkcs12 -export -out "$WORKDIR/dev.p12" \
        -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
        -passout pass:spacepill \
        -legacy -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

    echo "📥 Importing into login keychain..."
    security import "$WORKDIR/dev.p12" -k "$KEYCHAIN" -P spacepill \
        -T /usr/bin/codesign -T /usr/bin/security

    HASH=$(identity_hash)
    if [ -z "$HASH" ]; then
        echo "❌ Import succeeded but no identity appeared. Check the output above."
        exit 1
    fi
fi

# Without this, codesign gets errSecInternalComponent: it can see the key but
# is not on its ACL. This is the step that actually makes signing work -- it
# needs the real password, which is why we prompted for it above.
echo "🔓 Granting codesign access to the private key..."
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1 \
    || echo "⚠️  set-key-partition-list reported an error; continuing to the signing test."

echo "🔏 Test signing..."
if test_sign "$HASH"; then
    echo
    echo "✅ Done. './bin/start.sh' will now sign with '$CN' ($HASH)."
    echo "   Grant Accessibility + Input Monitoring once and the grants will stick"
    echo "   across rebuilds."
    echo
    echo "   Note: the certificate is intentionally left untrusted. codesign does"
    echo "   not require trust to sign, and marking it trusted needs a GUI"
    echo "   authorisation dialog that cannot appear over SSH."
else
    echo
    echo "❌ codesign still cannot use the key."
    echo "   Most likely the keychain re-locked or the password was wrong."
    echo "   Try again, or run this in a GUI terminal session:"
    echo "     security set-key-partition-list -S apple-tool:,apple:,codesign: -s '$KEYCHAIN'"
    exit 1
fi
