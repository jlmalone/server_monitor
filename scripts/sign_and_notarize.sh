#!/bin/bash
# Sign and Notarize ServerMonitor.app
# Usage: ./sign_and_notarize.sh

set -e

APP_PATH="dist/ServerMonitor.app"
DMG_PATH="dist/ServerMonitor.dmg"

# Load credentials from .env (see scripts/.env.example)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a; . "$PROJECT_ROOT/.env"; set +a
elif [ -f "$SCRIPT_DIR/.env" ]; then
    set -a; . "$SCRIPT_DIR/.env"; set +a
fi

: "${DEVELOPER_ID_IDENTITY:?Set DEVELOPER_ID_IDENTITY in .env}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID in .env}"

IDENTITY="$DEVELOPER_ID_IDENTITY"
TEAM_ID="$APPLE_TEAM_ID"
BUNDLE_ID="${BUNDLE_ID:-com.servermonitor.app}"

echo "🔐 Step 1: Code signing app bundle..."
codesign --force --options runtime --deep --sign "$IDENTITY" "$APP_PATH"

echo "✅ Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "📦 Step 2: Creating signed DMG..."
rm -f "$DMG_PATH"
mkdir -p dmg_temp
cp -R "$APP_PATH" dmg_temp/
hdiutil create -volname "ServerMonitor" -srcfolder dmg_temp -ov -format UDZO "$DMG_PATH"
rm -rf dmg_temp

echo "🔐 Step 3: Signing DMG..."
codesign --force --sign "$IDENTITY" "$DMG_PATH"

echo "📤 Step 4: Notarizing with Apple..."
echo "⚠️  You need an app-specific password from appleid.apple.com"
echo "Please enter your Apple ID email:"
read APPLE_ID
echo "Please enter your app-specific password:"
read -s APP_PASSWORD

xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APP_PASSWORD" \
  --team-id "$TEAM_ID" \
  --wait

echo "📎 Step 5: Stapling ticket..."
xcrun stapler staple "$DMG_PATH"

echo "✅ Done! ServerMonitor.dmg is signed and notarized"
echo "Verify: spctl -a -vvv -t install $DMG_PATH"
