#!/bin/bash
set -e

# Configuration
APP_NAME="ServerMonitor"
SCHEME="ServerMonitor"
BUILD_DIR="build"
CLI_DIR="../cli"
VERSION="1.0.0"

echo "🚀 Starting build process for $APP_NAME..."

# 1. Build CLI
echo "📦 Building CLI..."
pushd "$CLI_DIR"
npm install
npm run build
popd

# 2. Build Mac App
echo "📱 Building macOS App..."
cd ../app/ServerMonitor
xcodebuild -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
  archive

# Export Archive to App
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "$BUILD_DIR/Export"

# 3. Embed CLI into App
echo "📎 Embedding CLI into App Bundle..."
APP_BUNDLE="$BUILD_DIR/Export/$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/Resources/cli"
cp "$CLI_DIR/dist/sm" "$APP_BUNDLE/Contents/Resources/cli/"
chmod +x "$APP_BUNDLE/Contents/Resources/cli/sm"

# 4. Create DMG
echo "💿 Creating DMG..."
VOL_NAME="$APP_NAME"
DMG_PATH="../../$APP_NAME.dmg"
STAGING_DIR="$BUILD_DIR/dmg_staging"

# Clean up
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

# Copy App and Link Applications
cp -r "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Create DMG
hdiutil create -volname "$VOL_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

echo "🎉 Done! Installer created at $APP_NAME.dmg"
echo "   (Note: For public distribution, you must Sign and Notarize this DMG)"
