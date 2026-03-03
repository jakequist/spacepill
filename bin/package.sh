#!/bin/bash

set -eo pipefail

# Configuration
APP_NAME="SpacePill"
BUNDLE_ID="com.jakequist.spacepill"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=$(cat "$PROJECT_DIR/VERSION")
BUILD_NUMBER="1"
BUILD_DIR="$PROJECT_DIR/SpacePill/.build/release"
STAGING_DIR="$PROJECT_DIR/staging"
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"

echo "🚀 Building $APP_NAME v$VERSION..."

# 1. Clean staging and build artifacts
rm -rf "$STAGING_DIR"
rm -rf "$PROJECT_DIR/SpacePill/.build"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 2. Build executable
cd "$PROJECT_DIR/SpacePill"
swift build -c release

# 3. Create .app structure
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
cp "$PROJECT_DIR/SpacePill/SpacePill/Resources/Info.plist" "$APP_BUNDLE/Contents/"

# 4. Handle Icon
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

# 5. Sign and Notarize (If identity is provided)
# Usage: APPLE_IDENTITY="Developer ID Application: Your Name (TEAMID)" APPLE_ID="email@example.com" APPLE_PASSWORD="app-specific-password" ./bin/package.sh
if [ -n "$APPLE_IDENTITY" ]; then
    echo "SGN Signing $APP_BUNDLE..."
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
    echo "⚠️ Skipping signing: APPLE_IDENTITY not set."
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
