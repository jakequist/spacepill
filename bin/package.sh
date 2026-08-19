#!/bin/bash

set -eo pipefail

# Configuration
APP_NAME="SpacePill"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=$(cat "$PROJECT_DIR/VERSION")
# Canonical bundle identifier. Read from Info.plist so there is exactly one
# source of truth -- changing it would invalidate every existing user's
# Accessibility / Input Monitoring grants and their Launch-at-Login item.
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
    "$PROJECT_DIR/SpacePill/SpacePill/Resources/Info.plist")
BUILD_DIR="$PROJECT_DIR/SpacePill/.build/release"
STAGING_DIR="$PROJECT_DIR/staging"
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"

echo "🚀 Building $APP_NAME v$VERSION..."

# 1. Clean staging and build artifacts
rm -rf "$STAGING_DIR"
rm -rf "$PROJECT_DIR/SpacePill/.build"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Helpers"

# 2. Build executable
cd "$PROJECT_DIR/SpacePill"
swift build -c release

# 3. Create .app structure
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
# `spacepill`, the command-line client, rides along inside the bundle. Users
# run `spacepill install-cli` to symlink it into /usr/local/bin.
#
# Contents/Helpers rather than Contents/MacOS: macOS filesystems are
# case-insensitive by default, so `MacOS/spacepill` and `MacOS/SpacePill` are one
# and the same file and the copy would overwrite the app. That collision is also
# why the SwiftPM product is named SpacePillCLI.
cp "$BUILD_DIR/SpacePillCLI" "$APP_BUNDLE/Contents/Helpers/spacepill"
cp "$PROJECT_DIR/SpacePill/SpacePill/Resources/Info.plist" "$APP_BUNDLE/Contents/"

# Stamp the version from ./VERSION so the bundle never drifts from the repo.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_BUNDLE/Contents/Info.plist"
echo "🏷  Stamped $BUNDLE_ID v$VERSION"

# 4. Handle Icon
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

# 5. Sign and Notarize (If identity is provided)
# Usage: APPLE_IDENTITY="Developer ID Application: Your Name (TEAMID)" APPLE_ID="email@example.com" APPLE_PASSWORD="app-specific-password" ./bin/package.sh
if [ -n "$APPLE_IDENTITY" ]; then
    echo "SGN Signing $APP_BUNDLE..."
    # Nested first: the bundled `spacepill` CLI is separate code, and sealing an
    # unsigned binary into the bundle fails notarisation.
    codesign --force --options runtime --sign "$APPLE_IDENTITY" "$APP_BUNDLE/Contents/Helpers/spacepill"
    codesign --deep --force --options runtime --sign "$APPLE_IDENTITY" "$APP_BUNDLE"

    echo "📦 Creating ZIP for notarization..."
    ZIP_PATH="$STAGING_DIR/$APP_NAME.zip"
    cd "$STAGING_DIR" && zip -y -r "$ZIP_PATH" "$APP_NAME.app"

    if [ -n "$APPLE_ID" ] && [ -n "$APPLE_PASSWORD" ]; then
        echo "🚀 Submitting to Apple Notary Service..."
        xcrun notarytool submit "$ZIP_PATH" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            --wait

        echo "stapling ticket to app..."
        xcrun stapler staple "$APP_BUNDLE"

        # Cleanup notarization zip
        rm "$ZIP_PATH"
        echo "✅ Notarization complete."
    fi
else
    # No Developer ID: ad-hoc sign so the app still launches. An unsigned Mach-O
    # will not run at all on Apple Silicon, so "unsigned" has to mean ad-hoc, not
    # nothing. Gatekeeper will still warn and this cannot be notarized -- that is
    # what makes it a developer preview rather than a shippable build.
    echo "⚠️ No APPLE_IDENTITY; ad-hoc signing (developer preview, not notarizable)."
    codesign --force --sign - "$APP_BUNDLE/Contents/Helpers/spacepill"
    codesign --force --sign - "$APP_BUNDLE"
fi

# 6. Create DMG
echo "💿 Creating Disk Image (DMG)..."
DMG_PATH="$STAGING_DIR/$APP_NAME.dmg"
DMG_TEMP_DIR="$STAGING_DIR/dmg_temp"

rm -rf "$DMG_TEMP_DIR"
mkdir -p "$DMG_TEMP_DIR"

# Copy App to temp dir
cp -R "$APP_BUNDLE" "$DMG_TEMP_DIR/"

# Create symlink to /Applications
ln -s /Applications "$DMG_TEMP_DIR/Applications"

# Create the DMG
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP_DIR" -ov -format UDZO "$DMG_PATH"

# Cleanup temp dir
rm -rf "$DMG_TEMP_DIR"

echo "✅ Created $DMG_PATH"

# 7. Sign, notarize, and staple the DMG itself.
# The app inside is already notarized+stapled, so it launches cleanly once
# dragged out. But the DMG a user *downloads* carries a quarantine flag, and an
# un-notarized DMG still trips Gatekeeper on open. Notarizing and stapling the
# DMG makes the whole download pristine. Same credential gate as the app.
if [ -n "$APPLE_IDENTITY" ] && [ -n "$APPLE_ID" ] && [ -n "$APPLE_PASSWORD" ]; then
    echo "🔏 Signing and notarizing the DMG..."
    codesign --force --sign "$APPLE_IDENTITY" "$DMG_PATH"
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    echo "✅ DMG notarized and stapled."
fi
