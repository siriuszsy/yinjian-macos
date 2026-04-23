#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/voiceKey.xcodeproj"
SCHEME="voiceKey"
CONFIGURATION="GitHubRelease"
DERIVED_DIR="${DERIVED_DIR:-$ROOT_DIR/.derived-github-release}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/release-assets/github-release}"
ARCHIVE_PATH="$WORK_DIR/$SCHEME.xcarchive"
EXPORT_PATH="$WORK_DIR/export"
STAGING_PATH="$WORK_DIR/dmg-staging"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
LOCAL_SIGNING_CONFIG="$ROOT_DIR/voiceKey/Support/Signing.local.xcconfig"
NOTARY_PROFILE="${VOICEKEY_NOTARY_PROFILE:-voiceKey-notary}"
APP_NAME="voiceKey"
DMG_VOLUME_NAME="音键"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_command xcodebuild
require_command xcrun
require_command security
require_command ditto
require_command hdiutil
require_command shasum

if [[ ! -f "$LOCAL_SIGNING_CONFIG" ]]; then
  echo "Missing local signing config: $LOCAL_SIGNING_CONFIG" >&2
  exit 1
fi

TEAM_ID="$(awk -F'=' '/VOICEKEY_DEVELOPMENT_TEAM/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$LOCAL_SIGNING_CONFIG")"
if [[ -z "$TEAM_ID" ]]; then
  echo "Could not resolve VOICEKEY_DEVELOPMENT_TEAM from $LOCAL_SIGNING_CONFIG" >&2
  exit 1
fi

DEVELOPER_ID_IDENTITY="$(
  security find-identity -v -p codesigning 2>&1 \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }'
)"

if [[ -z "$DEVELOPER_ID_IDENTITY" ]]; then
  echo "No valid Developer ID Application identity found." >&2
  exit 1
fi

VERSION="$(xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings \
  | awk '/MARKETING_VERSION/ { print $3; exit }')"
BUILD_NUMBER="$(xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings \
  | awk '/CURRENT_PROJECT_VERSION/ { print $3; exit }')"

if [[ -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
  echo "Could not resolve version/build number from Xcode build settings." >&2
  exit 1
fi

ARCHIVED_APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
NOTARY_ZIP_PATH="$WORK_DIR/${APP_NAME}-${VERSION}-notary.zip"
FINAL_ZIP_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-macos.zip"
FINAL_DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-macos.dmg"
FINAL_ZIP_SHA_PATH="$FINAL_ZIP_PATH.sha256"
FINAL_DMG_SHA_PATH="$FINAL_DMG_PATH.sha256"

rm -rf "$WORK_DIR" "$DIST_DIR"
mkdir -p "$WORK_DIR" "$DIST_DIR"

echo "==> Archiving $APP_NAME $VERSION ($BUILD_NUMBER) with $DEVELOPER_ID_IDENTITY"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DIR" \
  -archivePath "$ARCHIVE_PATH" \
  archive

if [[ ! -d "$ARCHIVED_APP_PATH" ]]; then
  echo "Archived app not found at $ARCHIVED_APP_PATH" >&2
  exit 1
fi

echo "==> Copying archived app for notarization"
mkdir -p "$EXPORT_PATH"
ditto "$ARCHIVED_APP_PATH" "$APP_PATH"

echo "==> Verifying archived Developer ID signature"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed -n '1,16p'

echo "==> Creating notary ZIP for app bundle"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP_PATH"

echo "==> Notarizing app ZIP with profile $NOTARY_PROFILE"
xcrun notarytool submit "$NOTARY_ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling app"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> Building final ZIP"
ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP_PATH"

echo "==> Building DMG"
mkdir -p "$STAGING_PATH"
ditto "$APP_PATH" "$STAGING_PATH/$APP_NAME.app"
ln -s /Applications "$STAGING_PATH/Applications"
hdiutil create \
  -volname "$DMG_VOLUME_NAME" \
  -srcfolder "$STAGING_PATH" \
  -ov \
  -format UDZO \
  "$FINAL_DMG_PATH"

echo "==> Notarizing DMG"
xcrun notarytool submit "$FINAL_DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling DMG"
xcrun stapler staple "$FINAL_DMG_PATH"
xcrun stapler validate "$FINAL_DMG_PATH"

echo "==> Gatekeeper verification"
spctl -a -vv --type exec "$APP_PATH" || true

shasum -a 256 "$FINAL_ZIP_PATH" > "$FINAL_ZIP_SHA_PATH"
shasum -a 256 "$FINAL_DMG_PATH" > "$FINAL_DMG_SHA_PATH"

echo
echo "Built GitHub direct release:"
echo "  App: $APP_PATH"
echo "  DMG: $FINAL_DMG_PATH"
echo "  ZIP: $FINAL_ZIP_PATH"
echo "  DMG SHA: $FINAL_DMG_SHA_PATH"
echo "  ZIP SHA: $FINAL_ZIP_SHA_PATH"
