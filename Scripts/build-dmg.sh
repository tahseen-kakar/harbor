#!/bin/sh

set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_DIR/Harbor.xcodeproj"
SCHEME="Harbor"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PROJECT_DIR/build/DerivedData}"
STAGING_ROOT="${STAGING_ROOT:-$PROJECT_DIR/build/dmg-root}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/build/release}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
APP_NAME="Harbor.app"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"

echo "Building $APP_NAME ($CONFIGURATION)..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
  build

if [ ! -d "$APP_PATH" ]; then
  echo "Expected app bundle not found at $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0.0")"
DMG_NAME="Harbor-${VERSION}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

echo "Preparing DMG staging folder..."
rm -rf "$STAGING_ROOT"
mkdir -p "$STAGING_ROOT" "$OUTPUT_DIR"

ditto "$APP_PATH" "$STAGING_ROOT/$APP_NAME"
ln -s /Applications "$STAGING_ROOT/Applications"

rm -f "$DMG_PATH"

echo "Creating disk image..."
hdiutil create \
  -volname "Harbor" \
  -srcfolder "$STAGING_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo
echo "Created:"
echo "  $DMG_PATH"
echo
echo "When users open this DMG, they'll see Harbor.app and an Applications shortcut for drag-to-install."
echo "For public distribution, sign and notarize Harbor.app before shipping the DMG."
