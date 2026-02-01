#!/bin/bash
# Package ServerMonitor.app into a DMG for distribution with custom icon

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

APP_NAME="ServerMonitor"
VERSION="1.0.0"
CONFIGURATION="${1:-Debug}"  # Default to Debug, pass Release as argument
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/ServerMonitor-dlhtvtsxefmoelcierdjnhiqpguy/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_TEMP="${APP_NAME}-temp.dmg"
VOLUME_NAME="${APP_NAME}"

# Icon location - use the icns from the app assets
ICON_PATH="${PROJECT_ROOT}/app/AppIcon.icns"

# Fallback: try the asset catalog location
if [ ! -f "$ICON_PATH" ]; then
    ICON_PATH="${PROJECT_ROOT}/app/ServerMonitor/ServerMonitor/Assets.xcassets/AppIcon.appiconset/AppIcon.icns"
fi

if [ ! -f "$ICON_PATH" ]; then
    echo "⚠️  Warning: Icon not found at expected locations. DMG will have default icon."
    ICON_PATH=""
fi

# Clean up any existing DMG
rm -f "${DMG_NAME}" "${DMG_TEMP}"

echo "📦 Creating DMG from ${APP_PATH}..."
if [ -n "$ICON_PATH" ]; then
    echo "🎨 Using custom icon: ${ICON_PATH}"
fi

# Create temporary directory for DMG contents
TMP_DIR=$(mktemp -d)
cp -R "${APP_PATH}" "${TMP_DIR}/"

# Create symlink to Applications folder
ln -s /Applications "${TMP_DIR}/Applications"

# Copy icon as volume icon
if [ -n "$ICON_PATH" ]; then
    cp "${ICON_PATH}" "${TMP_DIR}/.VolumeIcon.icns"
fi

# Create a read-write DMG first (needed to set custom icon)
hdiutil create -volname "${VOLUME_NAME}" \
    -srcfolder "${TMP_DIR}" \
    -ov -format UDRW \
    "${DMG_TEMP}"

# Clean up temp folder
rm -rf "${TMP_DIR}"

# Mount the DMG to set the custom icon flag
if [ -n "$ICON_PATH" ]; then
    echo "🔧 Setting custom volume icon..."
    
    # Mount
    MOUNT_POINT=$(hdiutil attach -readwrite -noverify "${DMG_TEMP}" | grep "Volumes" | awk '{print $3}')
    
    if [ -n "$MOUNT_POINT" ]; then
        # Set the custom icon attribute on the volume
        # This tells Finder to use .VolumeIcon.icns
        SetFile -c icnC "${MOUNT_POINT}/.VolumeIcon.icns" 2>/dev/null || true
        SetFile -a C "${MOUNT_POINT}" 2>/dev/null || true
        
        # Sync and unmount
        sync
        hdiutil detach "${MOUNT_POINT}" -quiet
    else
        echo "⚠️  Could not mount DMG to set icon"
    fi
fi

# Convert to compressed read-only DMG
echo "📀 Converting to compressed DMG..."
hdiutil convert "${DMG_TEMP}" -format UDZO -o "${DMG_NAME}"

# Clean up temp DMG
rm -f "${DMG_TEMP}"

echo ""
echo "✅ Created ${DMG_NAME}"
if [ -n "$ICON_PATH" ]; then
    echo "🎨 Custom icon applied"
fi
echo ""
echo "Next steps:"
echo "1. Test the DMG: open ${DMG_NAME}"
echo "2. Notarize: ./scripts/notarize.sh ${DMG_NAME}"
echo "3. Upload to GitHub Releases"
