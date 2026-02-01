#!/bin/bash
# Build, sign, package, notarize, and staple ServerMonitor for release
# Usage: ./scripts/build-release.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

APP_NAME="ServerMonitor"
VERSION="1.0.0"
BUNDLE_ID="com.jmalone.ServerMonitor"
SIGNING_IDENTITY="Developer ID Application: Joseph Malone (44SCLSYCZZ)"

# Load credentials
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
elif [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
else
    echo "❌ Error: .env file not found. Create one with APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD"
    exit 1
fi

if [ -z "$APPLE_ID" ] || [ -z "$APPLE_TEAM_ID" ] || [ -z "$APPLE_APP_PASSWORD" ]; then
    echo "❌ Error: Missing Apple credentials in .env"
    echo "   Required: APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD"
    exit 1
fi

echo "🚀 Building $APP_NAME v$VERSION for release..."
echo ""

# Step 1: Build Release
echo "🔨 Step 1/6: Building Release configuration..."
cd "$PROJECT_ROOT/app/ServerMonitor"
xcodebuild -scheme ServerMonitor -configuration Release -derivedDataPath ./build clean build 2>&1 | grep -E "(error:|warning:|BUILD|Compiling)" || true

APP_PATH="$PROJECT_ROOT/app/ServerMonitor/build/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build failed: $APP_PATH not found"
    exit 1
fi
echo "   ✅ Build succeeded"

# Step 2: Sign the app with hardened runtime
echo ""
echo "🔐 Step 2/6: Signing app with hardened runtime..."
codesign --deep --force --verify --verbose \
    --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --timestamp \
    "$APP_PATH" 2>&1 | grep -v "^$"
echo "   ✅ App signed"

# Step 3: Create DMG with custom icon
echo ""
echo "📦 Step 3/6: Creating DMG..."
cd "$PROJECT_ROOT"
rm -f "${APP_NAME}-${VERSION}.dmg" "${APP_NAME}-temp.dmg"
hdiutil detach "/Volumes/${APP_NAME}" 2>/dev/null || true

# Icon for DMG volume
ICON_PATH="$PROJECT_ROOT/app/AppIcon.icns"
if [ ! -f "$ICON_PATH" ]; then
    ICON_PATH="$PROJECT_ROOT/app/ServerMonitor/ServerMonitor/Assets.xcassets/AppIcon.appiconset/AppIcon.icns"
fi

TMP_DIR=$(mktemp -d)
cp -R "$APP_PATH" "$TMP_DIR/"
ln -s /Applications "$TMP_DIR/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$TMP_DIR" -ov -format UDRW "${APP_NAME}-temp.dmg"
rm -rf "$TMP_DIR"

# Set volume icon
if [ -f "$ICON_PATH" ]; then
    MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify "${APP_NAME}-temp.dmg")
    MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep "Volumes" | awk -F'\t' '{print $NF}' | xargs)
    if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
        cp "$ICON_PATH" "$MOUNT_POINT/.VolumeIcon.icns"
        SetFile -c icnC "$MOUNT_POINT/.VolumeIcon.icns" 2>/dev/null || true
        SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
        sync && sleep 1
        hdiutil detach "$MOUNT_POINT" -quiet || hdiutil detach "$MOUNT_POINT" -force
    fi
fi

hdiutil convert "${APP_NAME}-temp.dmg" -format UDZO -o "${APP_NAME}-${VERSION}.dmg"
rm -f "${APP_NAME}-temp.dmg"
echo "   ✅ DMG created"

# Step 4: Sign the DMG
echo ""
echo "🔐 Step 4/6: Signing DMG..."
codesign --sign "$SIGNING_IDENTITY" --timestamp "${APP_NAME}-${VERSION}.dmg"
echo "   ✅ DMG signed"

# Step 5: Notarize
echo ""
echo "📤 Step 5/6: Notarizing with Apple (this may take a few minutes)..."
xcrun notarytool submit "${APP_NAME}-${VERSION}.dmg" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait

# Step 6: Staple
echo ""
echo "📎 Step 6/6: Stapling notarization ticket..."
xcrun stapler staple "${APP_NAME}-${VERSION}.dmg"
echo "   ✅ Stapled"

# Move to docs for GitHub Pages
echo ""
echo "📁 Moving to docs/ for GitHub Pages..."
mv "${APP_NAME}-${VERSION}.dmg" docs/

echo ""
echo "=============================================="
echo "✅ BUILD COMPLETE: docs/${APP_NAME}-${VERSION}.dmg"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  git add -A && git commit -m 'Release v${VERSION}' && git push origin master"
echo ""
ls -lh "docs/${APP_NAME}-${VERSION}.dmg"
