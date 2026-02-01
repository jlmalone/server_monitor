#!/bin/bash
# Notarize a DMG with Apple
# Usage: ./notarize.sh ServerMonitor-1.0.0.dmg

set -e

DMG_PATH="$1"

if [ -z "$DMG_PATH" ]; then
  echo "Usage: ./notarize.sh <path-to-dmg>"
  exit 1
fi

if [ ! -f "$DMG_PATH" ]; then
  echo "Error: DMG not found at $DMG_PATH"
  exit 1
fi

# You'll need these environment variables:
# APPLE_ID - your Apple ID email
# APPLE_TEAM_ID - your Team ID from developer.apple.com
# APPLE_APP_PASSWORD - app-specific password from appleid.apple.com

if [ -z "$APPLE_ID" ] || [ -z "$APPLE_TEAM_ID" ]; then
  echo "⚠️  Required environment variables:"
  echo ""
  echo "export APPLE_ID='your.email@example.com'"
  echo "export APPLE_TEAM_ID='YOUR10CHAR'"
  echo "export APPLE_APP_PASSWORD='xxxx-xxxx-xxxx-xxxx'"
  echo ""
  echo "Get app-specific password at: https://appleid.apple.com/account/manage"
  echo "Find Team ID at: https://developer.apple.com/account"
  exit 1
fi

echo "🔐 Notarizing ${DMG_PATH}..."
echo ""

# Submit for notarization
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

# Staple the notarization ticket
echo ""
echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo ""
echo "✅ Notarization complete!"
echo ""
echo "To verify:"
echo "  spctl -a -t open --context context:primary-signature -v ${DMG_PATH}"
