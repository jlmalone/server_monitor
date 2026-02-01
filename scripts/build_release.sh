#!/bin/bash
# Complete build pipeline for ServerMonitor
# Handles: icon processing, building, signing, DMG creation, notarization

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Configuration
ICON_SOURCE="${1:-app/icon-rounded.png}"
APP_NAME="ServerMonitor"
IDENTITY="Developer ID Application: Joseph Malone (44SCLSYCZZ)"
TEAM_ID="44SCLSYCZZ"
APPLE_ID="jlawrenceiv@gmail.com"
APP_PASSWORD="${SERVERMONITOR_NOTARIZATION_PASSWORD:-scwg-gafm-zyma-iuzx}"

echo "🚀 ServerMonitor Release Build Pipeline"
echo "========================================"

# Step 1: Process icon
echo ""
echo "🎨 Step 1: Processing icon..."
if [ ! -f "$ICON_SOURCE" ]; then
    echo "❌ Icon not found: $ICON_SOURCE"
    exit 1
fi

# Generate iconset
rm -rf app/AppIcon.iconset
mkdir -p app/AppIcon.iconset
for size in 16 32 64 128 256 512 1024; do
    sips -z $size $size "$ICON_SOURCE" --out "app/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null 2>&1
done

# Convert to .icns
iconutil -c icns app/AppIcon.iconset -o app/AppIcon.icns
echo "✅ Icon generated: app/AppIcon.icns"

# Step 2: Build Xcode project
echo ""
echo "🔨 Step 2: Building Xcode project..."
cd app/ServerMonitor
xcodebuild -project ServerMonitor.xcodeproj \
    -scheme ServerMonitor \
    -configuration Release \
    clean build | grep -E "^\*\*|Building|Signing" || true
cd "$PROJECT_ROOT"

BUILT_APP="$HOME/Library/Developer/Xcode/DerivedData/ServerMonitor-dlhtvtsxefmoelcierdjnhiqpguy/Build/Products/Release/ServerMonitor.app"
echo "✅ Build complete"

# Step 3: Copy to dist and add icon
echo ""
echo "📦 Step 3: Preparing app bundle..."
rm -rf dist/ServerMonitor.app
mkdir -p dist
cp -R "$BUILT_APP" dist/

# Add icon to Resources
mkdir -p "dist/ServerMonitor.app/Contents/Resources"
cp app/AppIcon.icns "dist/ServerMonitor.app/Contents/Resources/AppIcon.icns"

# Update Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" \
    "dist/ServerMonitor.app/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" \
    "dist/ServerMonitor.app/Contents/Info.plist"

echo "✅ App bundle prepared with icon"

# Step 4: Code sign app
echo ""
echo "🔐 Step 4: Code signing..."
codesign --force --options runtime --deep --sign "$IDENTITY" dist/ServerMonitor.app
codesign --verify --deep --strict --verbose=2 dist/ServerMonitor.app
echo "✅ App signed"

# Step 5: Create DMG
echo ""
echo "💿 Step 5: Creating DMG..."
rm -rf dmg_source dist/ServerMonitor.dmg dist/ServerMonitor-temp.dmg
mkdir -p dmg_source
cp -R dist/ServerMonitor.app dmg_source/
ln -s /Applications dmg_source/Applications

# Create read-write DMG
hdiutil create -volname "$APP_NAME" -srcfolder dmg_source \
    -ov -format UDRW dist/ServerMonitor-temp.dmg >/dev/null

# Mount and add custom icon
device=$(hdiutil attach -readwrite -noverify -noautoopen dist/ServerMonitor-temp.dmg 2>&1 | \
    grep "^/dev/" | awk '{print $1}' | head -1)
sleep 2
cp app/AppIcon.icns "/Volumes/$APP_NAME/.VolumeIcon.icns" 2>/dev/null || echo "Note: Could not set custom DMG icon"
SetFile -c icnC "/Volumes/$APP_NAME/.VolumeIcon.icns" 2>/dev/null || true
SetFile -a C "/Volumes/$APP_NAME" 2>/dev/null || true
sleep 1
hdiutil detach "$device" >/dev/null 2>&1 || hdiutil detach "/Volumes/$APP_NAME" >/dev/null 2>&1 || true

# Convert to compressed read-only
hdiutil convert dist/ServerMonitor-temp.dmg -format UDZO \
    -o dist/ServerMonitor.dmg >/dev/null
rm dist/ServerMonitor-temp.dmg dmg_source -rf

echo "✅ DMG created with Applications folder and custom icon"

# Step 6: Sign DMG
echo ""
echo "🔐 Step 6: Signing DMG..."
codesign --force --sign "$IDENTITY" dist/ServerMonitor.dmg
echo "✅ DMG signed"

# Step 7: Notarize
echo ""
echo "📤 Step 7: Notarizing with Apple (this takes 2-5 minutes)..."
xcrun notarytool submit dist/ServerMonitor.dmg \
    --apple-id "$APPLE_ID" \
    --password "$APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait

# Step 8: Staple
echo ""
echo "📎 Step 8: Stapling notarization ticket..."
xcrun stapler staple dist/ServerMonitor.dmg

# Step 9: Verify
echo ""
echo "✅ Step 9: Verifying..."
spctl -a -vvv -t install dist/ServerMonitor.dmg

# Done!
echo ""
echo "🎉 SUCCESS! Release build complete"
echo "======================================"
echo ""
ls -lh dist/ServerMonitor.dmg
echo ""
echo "Ready to publish:"
echo "  • Signed with Developer ID ✅"
echo "  • Notarized by Apple ✅"
echo "  • Custom icon ✅"
echo "  • Applications folder symlink ✅"
echo ""
echo "Next: ./scripts/publish_github.sh"
