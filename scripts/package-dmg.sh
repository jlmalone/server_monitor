#!/bin/bash
# Package ServerMonitor.app into a DMG for distribution

set -e

APP_NAME="ServerMonitor"
VERSION="1.0.0"
CONFIGURATION="${1:-Debug}"  # Default to Debug, pass Release as argument
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/ServerMonitor-dlhtvtsxefmoelcierdjnhiqpguy/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
VOLUME_NAME="${APP_NAME}"

# Clean up any existing DMG
rm -f "${DMG_NAME}"

echo "📦 Creating DMG from ${APP_PATH}..."

# Create temporary directory for DMG contents
TMP_DIR=$(mktemp -d)
cp -R "${APP_PATH}" "${TMP_DIR}/"

# Create symlink to Applications folder
ln -s /Applications "${TMP_DIR}/Applications"

# Create DMG
hdiutil create -volname "${VOLUME_NAME}" \
  -srcfolder "${TMP_DIR}" \
  -ov -format UDZO \
  "${DMG_NAME}"

# Clean up
rm -rf "${TMP_DIR}"

echo "✅ Created ${DMG_NAME}"
echo ""
echo "Next steps:"
echo "1. Test the DMG: open ${DMG_NAME}"
echo "2. Notarize: ./scripts/notarize.sh ${DMG_NAME}"
echo "3. Upload to GitHub Releases"
