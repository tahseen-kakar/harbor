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
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
SIGN_TORRENT_RUNTIME="${SIGN_TORRENT_RUNTIME:-YES}"
APP_NAME="Harbor.app"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"

sign_path() {
  target_path="$1"

  if [ -z "$SIGNING_IDENTITY" ]; then
    return
  fi

  /usr/bin/codesign \
    --force \
    --timestamp \
    --options runtime \
    --sign "$SIGNING_IDENTITY" \
    "$target_path"
}

echo "Building $APP_NAME ($CONFIGURATION)..."
if [ -n "$SIGNING_IDENTITY" ]; then
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    build
else
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
    build
fi

if [ ! -d "$APP_PATH" ]; then
  echo "Expected app bundle not found at $APP_PATH" >&2
  exit 1
fi

if [ -n "$SIGNING_IDENTITY" ] && [ "$SIGN_TORRENT_RUNTIME" = "YES" ]; then
  echo "Signing bundled torrent runtime..."

  find "$APP_PATH/Contents/Resources/TorrentRuntime" \
    -type f \
    \( -name "*.dylib" -o -perm -111 \) \
    | sort \
    | while IFS= read -r runtime_file; do
        sign_path "$runtime_file"
      done

  echo "Re-signing app bundle..."
  sign_path "$APP_PATH"

  echo "Verifying signature..."
  /usr/bin/codesign --verify --verbose=2 "$APP_PATH"
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
if [ -n "$SIGNING_IDENTITY" ]; then
  echo "Signed with:"
  echo "  $SIGNING_IDENTITY"
  echo "Notarize the signed app or DMG before public distribution."
else
  echo "For public distribution, sign and notarize Harbor.app before shipping the DMG."
fi
