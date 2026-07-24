#!/bin/bash
# Canonical Server Monitor release pipeline: build, sign nested code inside-out,
# package a DMG, and optionally notarize/staple it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
XCODE_PROJECT="$PROJECT_ROOT/app/ServerMonitor/ServerMonitor.xcodeproj"
SCHEME="ServerMonitor"
BUILD_ROOT="$PROJECT_ROOT/build/release"
DIST_DIR="$PROJECT_ROOT/dist"
NOTARIZE=0

usage() {
  echo "Usage: ./scripts/build_release.sh [--notarize]" >&2
}
for arg in "$@"; do
  case "$arg" in
    --notarize) NOTARIZE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a; source "$PROJECT_ROOT/.env"; set +a
elif [[ -f "$SCRIPT_DIR/.env" ]]; then
  set -a; source "$SCRIPT_DIR/.env"; set +a
fi

IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | sed -n '1p')"
fi
[[ -n "$IDENTITY" ]] || {
  echo "ERROR: no Developer ID Application identity found; set DEVELOPER_ID_IDENTITY" >&2
  exit 1
}

IDENTITY_TEAM="$(sed -n 's/.*(\([A-Z0-9][A-Z0-9]*\))$/\1/p' <<<"$IDENTITY")"
TEAM_ID="${APPLE_TEAM_ID:-$IDENTITY_TEAM}"
[[ -n "$TEAM_ID" ]] || {
  echo "ERROR: unable to derive Team ID; set APPLE_TEAM_ID" >&2
  exit 1
}

rm -rf "$BUILD_ROOT" "$DIST_DIR"
mkdir -p "$BUILD_ROOT" "$DIST_DIR"

xcodebuild \
  -project "$XCODE_PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_ROOT" \
  CODE_SIGNING_ALLOWED=NO \
  clean build

BUILT_APP="$BUILD_ROOT/Build/Products/Release/ServerMonitor.app"
[[ -d "$BUILT_APP" ]] || { echo "ERROR: build product missing: $BUILT_APP" >&2; exit 1; }
cp -R "$BUILT_APP" "$DIST_DIR/ServerMonitor.app"
APP="$DIST_DIR/ServerMonitor.app"
AGENT="$APP/Contents/Resources/InfrastructureAgent"
AGENT_PLIST="$APP/Contents/Library/LaunchAgents/vision.salient.InfrastructureAgent.plist"

[[ -x "$AGENT" ]] || { echo "ERROR: embedded InfrastructureAgent missing" >&2; exit 1; }
[[ -f "$AGENT_PLIST" ]] || { echo "ERROR: embedded LaunchAgent plist missing" >&2; exit 1; }
# Xcode's generated Info.plist omits CFBundleIconFile even though the build
# setting is present. Add it before signing so Finder and Login Items use the
# bundled icon instead of a generic executable glyph.
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile AppIcon' "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" "$AGENT_PLIST"

for executable in "$APP/Contents/MacOS/ServerMonitor" "$AGENT"; do
  lipo "$executable" -verify_arch arm64 x86_64 >/dev/null || {
    echo "ERROR: release executable is not universal: $executable" >&2
    exit 1
  }
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
ICON_FILE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP/Contents/Info.plist")"
[[ "$BUNDLE_ID" == "vision.salient.ServerMonitor" ]] || {
  echo "ERROR: unexpected bundle identifier: $BUNDLE_ID" >&2
  exit 1
}
[[ "$ICON_FILE" == "AppIcon" && -f "$APP/Contents/Resources/AppIcon.icns" ]] || {
  echo "ERROR: app icon metadata/resource is incomplete" >&2
  exit 1
}

# Nested code must be sealed before the containing app. Do not use --deep for
# signing: it can hide an incorrectly signed nested payload.
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$AGENT"
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

for item in "$AGENT" "$APP"; do
  actual_team="$(codesign -dv --verbose=4 "$item" 2>&1 \
    | sed -n 's/^TeamIdentifier=//p')"
  [[ "$actual_team" == "$TEAM_ID" ]] || {
    echo "ERROR: signing team mismatch for $item (got '$actual_team', expected '$TEAM_ID')" >&2
    exit 1
  }
done

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/server-monitor-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
DMG="$DIST_DIR/ServerMonitor-$VERSION.dmg"
hdiutil create -quiet -volname "ServerMonitor" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --verbose=2 "$DMG"

if [[ "$NOTARIZE" == 1 ]]; then
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  else
    : "${APPLE_ID:?Set APPLE_ID or NOTARY_PROFILE for notarization}"
    : "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD or NOTARY_PROFILE for notarization}"
    xcrun notarytool submit "$DMG" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_PASSWORD" \
      --team-id "$TEAM_ID" \
      --wait
  fi
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -t open --context context:primary-signature -vv "$DMG"
fi

echo "Signed app: $APP"
echo "Signed DMG: $DMG"
if [[ "$NOTARIZE" == 0 ]]; then
  echo "Notarization skipped; rerun with --notarize for a distributable release."
fi
