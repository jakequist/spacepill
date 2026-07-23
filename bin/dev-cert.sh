#!/bin/bash
#
# Create a self-signed "SpacePill Dev" code signing identity in a dedicated,
# non-interactive keychain.
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
# WHY A SEPARATE KEYCHAIN
#   The login keychain requires user authorisation to release a private key, and
#   that authorisation cannot be granted from a background/SSH session -- exactly
#   where builds tend to run. Instead this creates a throwaway keychain holding
#   nothing but the dev certificate, with a random password stored 0600 at
#   ~/.spacepill/dev-keychain-password, which bin/start.sh unlocks automatically.
#   Your login keychain is never touched.
#
#   Trade-off: anything running as your user can read that password and sign as
#   "SpacePill Dev", inheriting SpacePill's permission grants. That is not much
#   of an escalation -- code running as you could tamper with the app anyway --
#   but it is the reason this is a dev-only tool. Never ship with this identity.
#
# USAGE
#   ./bin/dev-cert.sh          create the identity (idempotent)
#   ./bin/dev-cert.sh --check  report on the existing identity and exit
#
#   Fully non-interactive. No password prompts, works over SSH.
#
# TO UNDO
#   security delete-keychain ~/Library/Keychains/spacepill-dev.keychain-db
#   rm ~/.spacepill/dev-keychain-password

set -euo pipefail

CN="SpacePill Dev"
KEYCHAIN="$HOME/Library/Keychains/spacepill-dev.keychain-db"
KEYCHAIN_SHORT="spacepill-dev.keychain"
PASSWORD_FILE="$HOME/.spacepill/dev-keychain-password"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# `find-identity -v` lists only *trusted* identities, and a self-signed cert is
# never trusted, so the check must not use -v.
identity_hash() {
    [ -f "$KEYCHAIN" ] || return 0
    security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
        | awk -v cn="\"$CN\"" '$0 ~ cn {print $2; exit}'
}

# codesign refuses to use a key it cannot read, so the only honest test is to
# actually sign something.
test_sign() {
    local hash="$1"
    local probe="$WORKDIR/probe"
    cp /usr/bin/true "$probe"
    codesign --force --sign "$hash" --keychain "$KEYCHAIN" "$probe" >/dev/null 2>&1
}

unlock() {
    security unlock-keychain -p "$(cat "$PASSWORD_FILE")" "$KEYCHAIN"
}

if [ "${1:-}" = "--check" ]; then
    if [ ! -f "$KEYCHAIN" ] || [ ! -f "$PASSWORD_FILE" ]; then
        echo "❌ No dev signing keychain found. Run ./bin/dev-cert.sh"
        exit 1
    fi
    unlock
    HASH=$(identity_hash)
    if [ -z "$HASH" ]; then
        echo "❌ Keychain exists but holds no '$CN' identity. Re-run ./bin/dev-cert.sh"
        exit 1
    fi
    if test_sign "$HASH"; then
        echo "✅ '$CN' ($HASH) is present and can sign non-interactively."
    else
        echo "❌ '$CN' exists but codesign cannot use its private key."
        exit 1
    fi
    exit 0
fi

mkdir -p "$(dirname "$PASSWORD_FILE")"

if [ ! -f "$PASSWORD_FILE" ]; then
    # openssl rand rather than `tr </dev/urandom | head`: under `set -o pipefail`
    # head closing the pipe kills tr with SIGPIPE and takes the script with it.
    umask 077
    openssl rand -hex 24 > "$PASSWORD_FILE"
fi
chmod 600 "$PASSWORD_FILE"
KEYCHAIN_PASSWORD=$(cat "$PASSWORD_FILE")

if [ ! -f "$KEYCHAIN" ]; then
    echo "🔐 Creating dedicated signing keychain..."
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_SHORT"
fi

# No auto-lock: relocking would break unattended builds, and this keychain
# holds nothing but a local dev certificate.
security set-keychain-settings "$KEYCHAIN"
unlock

# Keep it on the search list so plain `codesign -s "SpacePill Dev"` and
# `find-identity` resolve without an explicit --keychain.
if ! security list-keychains -d user | grep -q "$KEYCHAIN_SHORT"; then
    EXISTING=$(security list-keychains -d user | sed 's/[" ]//g')
    # shellcheck disable=SC2086
    security list-keychains -d user -s $EXISTING "$KEYCHAIN"
fi

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

    echo "📥 Importing into the signing keychain..."
    security import "$WORKDIR/dev.p12" -k "$KEYCHAIN" -P spacepill \
        -T /usr/bin/codesign -T /usr/bin/security -A

    HASH=$(identity_hash)
    if [ -z "$HASH" ]; then
        echo "❌ Import succeeded but no identity appeared. Check the output above."
        exit 1
    fi
fi

# Without this codesign gets errSecInternalComponent: it can see the key but is
# not on its ACL. Unlike the login keychain, we know this password, so it can
# be set without any prompt.
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
    if security find-identity -p codesigning "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null | grep -q "$CN"; then
        echo "   FYI an older '$CN' cert is still sitting in your login keychain from"
        echo "   an earlier attempt. It is unused; remove it whenever convenient with:"
        echo "     security delete-identity -c \"$CN\" ~/Library/Keychains/login.keychain-db"
    fi
else
    echo
    echo "❌ codesign still cannot use the key. Check the output above."
    exit 1
fi
