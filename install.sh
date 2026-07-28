#!/bin/sh
#
# SpacePill installer.
#
#   curl -fsSL https://jakequist.github.io/spacepill/install.sh | sh
#
# Downloads the latest signed release, installs it to /Applications, launches
# it, and offers to put the `spacepill` CLI on your PATH. No dependencies beyond
# what ships with macOS.

set -eu

APP_NAME="SpacePill"
DMG_URL="https://github.com/jakequist/spacepill/releases/latest/download/SpacePill.dmg"
APPLICATIONS="/Applications"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
ok()    { printf '\033[1;32m✓\033[0m %s\n' "$1"; }
warn()  { printf '\033[1;33m!\033[0m %s\n' "$1"; }
die()   { printf '\033[1;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || die "SpacePill is macOS only."

TMP="$(mktemp -d)"
MOUNT=""
cleanup() {
    [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
    rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

info "Downloading the latest $APP_NAME..."
curl -fSL --progress-bar "$DMG_URL" -o "$TMP/$APP_NAME.dmg" \
    || die "Download failed. Check https://github.com/jakequist/spacepill/releases"

info "Mounting..."
MOUNT="$TMP/mnt"
mkdir -p "$MOUNT"
hdiutil attach "$TMP/$APP_NAME.dmg" -nobrowse -mountpoint "$MOUNT" -quiet \
    || die "Could not mount the disk image."

# Replace any existing copy. Quit it first so files aren't in use.
osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1

# /Applications is usually user-writable; fall back to sudo if not. sudo can
# still prompt here because it reads the password from the terminal, not stdin.
if [ -w "$APPLICATIONS" ]; then SUDO=""; else
    warn "$APPLICATIONS needs admin rights; you may be prompted for your password."
    SUDO="sudo"
fi

info "Installing to $APPLICATIONS..."
$SUDO rm -rf "$APPLICATIONS/$APP_NAME.app"
$SUDO cp -R "$MOUNT/$APP_NAME.app" "$APPLICATIONS/"

# The release is notarized, so this is just belt-and-suspenders against the
# quarantine flag a piped download can carry.
$SUDO xattr -dr com.apple.quarantine "$APPLICATIONS/$APP_NAME.app" 2>/dev/null || true

hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
MOUNT=""

info "Launching..."
open "$APPLICATIONS/$APP_NAME.app"

# Offer the CLI. `install-cli` symlinks into /usr/local/bin and explains itself
# if it needs sudo, so don't hard-fail the install if it can't.
CLI="$APPLICATIONS/$APP_NAME.app/Contents/Helpers/spacepill"
if [ -x "$CLI" ]; then
    "$CLI" install-cli >/dev/null 2>&1 \
        && ok "The 'spacepill' CLI is on your PATH." \
        || warn "To add the CLI later: $CLI install-cli"
fi

ok "$APP_NAME is installed and running — look for the pill in your menu bar."
