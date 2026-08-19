#!/bin/bash

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CURRENT_VERSION=$(cat "$PROJECT_DIR/VERSION")
echo "🚀 Starting release for v$CURRENT_VERSION..."

# 2. Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo "⚠️ You have uncommitted changes. Please commit or stash them before releasing."
    exit 1
fi

# 3. Check if tag already exists
if git rev-parse "v$CURRENT_VERSION" >/dev/null 2>&1; then
    echo "❌ Tag v$CURRENT_VERSION already exists. Please update VERSION in $PACKAGE_SH manually."
    exit 1
fi

# 4. Create and push tag
echo "🏷 Creating tag v$CURRENT_VERSION..."
git tag "v$CURRENT_VERSION"
git push origin main --tags

# 5. Build and Package (This includes signing/notarization if vars are set)
echo "📦 Building and packaging SpacePill..."
./bin/package.sh

# 6. Verify the dmg exists
DMG_PATH="staging/SpacePill.dmg"
if [ ! -f "$DMG_PATH" ]; then
    echo "❌ Packaging failed. No dmg found at $DMG_PATH"
    exit 1
fi

# 7. Create GitHub Release using gh cli
echo "🚀 Creating GitHub Release v$CURRENT_VERSION..."
gh release create "v$CURRENT_VERSION" "$DMG_PATH" \
    --title "Release v$CURRENT_VERSION" \
    --notes "Release v$CURRENT_VERSION of SpacePill"

echo "✅ v$CURRENT_VERSION released successfully to GitHub!"
