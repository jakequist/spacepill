#!/bin/bash
#
# Build SpacePill and run it as a real .app bundle.
#
# Why a bundle and not just ./.build/release/SpacePill?
#   - Bundle.main.bundleIdentifier is nil for a bare executable, which silently
#     disables Launch at Login (SMAppService) and changes the app's identity.
#   - TCC (Accessibility / Input Monitoring) grants are keyed to a bundle
#     identity at a stable path. Grants you click through for the bare binary
#     never apply to the shipped app.
#
# Usage:
#   ./bin/start.sh              build, then run in the foreground
#   ./bin/start.sh -d           build, then run detached in the background
#   ./bin/start.sh --debug      build the debug configuration (faster compiles)
#
# Logs go to the unified log, not this terminal. Stream them with ./bin/logs.sh

set -euo pipefail

DAEMON_MODE=false
CONFIG="release"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--daemon) DAEMON_MODE=true; shift ;;
        --debug) CONFIG="debug"; shift ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown parameter: $1" >&2; exit 1 ;;
    esac
done

APP_NAME="SpacePill"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$PROJECT_DIR/staging/$APP_NAME.app"

echo "🔨 Building ($CONFIG)..."
cd "$PROJECT_DIR/SpacePill"
swift build -c "$CONFIG"
BUILT_BINARY="$PROJECT_DIR/SpacePill/.build/$CONFIG/$APP_NAME"

echo "📦 Assembling $APP_NAME.app..."
pkill -x "$APP_NAME" 2>/dev/null || true

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILT_BINARY" "$APP_BUNDLE/Contents/MacOS/"
cp "$PROJECT_DIR/SpacePill/SpacePill/Resources/Info.plist" "$APP_BUNDLE/Contents/"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(cat "$PROJECT_DIR/VERSION")" \
    "$APP_BUNDLE/Contents/Info.plist" >/dev/null

# Prefer a real identity when one exists: an ad-hoc signature gets a new cdhash
# on every rebuild, so macOS treats each build as a brand new app and drops the
# Accessibility / Input Monitoring grants. CLAUDE.md explains how to create a
# self-signed "SpacePill Dev" certificate that keeps those grants stable.
# Match on the SHA-1 hash rather than the name, and without `-v`: a self-signed
# certificate is never "valid" in the trust sense, so `find-identity -v` would
# never list it. codesign does not need trust in order to sign.
SIGN_IDENTITY="${SPACEPILL_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -p codesigning 2>/dev/null \
        | awk '/"SpacePill Dev"/ {print $2; exit}')
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo "🔏 Signing as: $SIGN_IDENTITY"
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
    echo "🔏 Signing ad-hoc (permissions must be re-granted after each rebuild)"
    codesign --force --sign - "$APP_BUNDLE"
fi

if [ "$DAEMON_MODE" = true ]; then
    open "$APP_BUNDLE"
    echo "✅ $APP_NAME started in the background."
    echo "   Logs: ./bin/logs.sh"
else
    echo "✅ Running. Logs: ./bin/logs.sh   (Ctrl-C to quit)"
    exec "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi
