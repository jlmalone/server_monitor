#!/bin/bash
# Package ServerMonitor.app into a DMG for distribution with custom icon

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

APP_NAME="ServerMonitor"
VERSION="1.0.0"
CONFIGURATION="${1:-Debug}"  # Default to Debug, pass Release as argument

# Try project-local build first, then DerivedData
APP_PATH="${PROJECT_ROOT}/app/ServerMonitor/build/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    # Fallback: search in DerivedData
    APP_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/${CONFIGURATION}/${APP_NAME}.app" -type d 2>/dev/null | head -1)
fi

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: Could not find ${APP_NAME}.app for ${CONFIGURATION} configuration"
    echo "   Build the app first: xcodebuild -scheme ServerMonitor -configuration ${CONFIGURATION} build"
    exit 1
fi

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_TEMP="${APP_NAME}-temp.dmg"
VOLUME_NAME="${APP_NAME}"

# Icon location - use the icns from the app folder
ICON_PATH="${PROJECT_ROOT}/app/AppIcon.icns"

# Fallback: try the asset catalog location
if [ ! -f "$ICON_PATH" ]; then
    ICON_PATH="${PROJECT_ROOT}/app/ServerMonitor/ServerMonitor/Assets.xcassets/AppIcon.appiconset/AppIcon.icns"
fi

if [ ! -f "$ICON_PATH" ]; then
    echo "⚠️  Warning: Icon not found at expected locations. DMG will have default icon."
    ICON_PATH=""
else
    echo "🎨 Using custom icon: ${ICON_PATH}"
fi

# Clean up any existing DMG
rm -f "${DMG_NAME}" "${DMG_TEMP}"
hdiutil detach "/Volumes/${VOLUME_NAME}" 2>/dev/null || true

echo "📦 Creating DMG from ${APP_PATH}..."

# Create temporary directory for DMG contents
TMP_DIR=$(mktemp -d)
cp -R "${APP_PATH}" "${TMP_DIR}/"

# Create symlink to Applications folder
ln -s /Applications "${TMP_DIR}/Applications"

# Create a read-write DMG first (needed to set custom icon)
hdiutil create -volname "${VOLUME_NAME}" \
    -srcfolder "${TMP_DIR}" \
    -ov -format UDRW \
    "${DMG_TEMP}"

# Clean up temp folder
rm -rf "${TMP_DIR}"

# Set custom volume icon
if [ -n "$ICON_PATH" ]; then
    echo "🔧 Setting custom volume icon..."
    
    # Mount the DMG read-write
    MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify "${DMG_TEMP}")
    MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep "Volumes" | awk -F'\t' '{print $NF}' | xargs)
    
    if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
        echo "   Mounted at: $MOUNT_POINT"
        
        # Copy icon to volume root as .VolumeIcon.icns
        cp "${ICON_PATH}" "${MOUNT_POINT}/.VolumeIcon.icns"
        
        # Set the custom icon attribute on the volume
        SetFile -c icnC "${MOUNT_POINT}/.VolumeIcon.icns" 2>/dev/null || echo "   SetFile -c skipped"
        SetFile -a C "${MOUNT_POINT}" 2>/dev/null || echo "   SetFile -a skipped"
        
        # Sync and unmount
        sync
        sleep 1
        hdiutil detach "$MOUNT_POINT" -quiet || hdiutil detach "$MOUNT_POINT" -force
        echo "   ✅ Custom icon set"
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
ls -lh "${DMG_NAME}"
echo ""
echo "Next steps:"
echo "1. Test the DMG: open ${DMG_NAME}"
echo "2. Sign & Notarize: ./scripts/sign-and-notarize.sh ${DMG_NAME}"
echo "3. Upload to docs/ for GitHub Pages"
