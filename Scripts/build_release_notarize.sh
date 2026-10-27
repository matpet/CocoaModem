#!/usr/bin/env bash
set -euo pipefail

# Build a universal Release app, sign it with Developer ID, notarize, and staple.
# Required env vars:
#   DEVELOPER_ID_APP: e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_KEYCHAIN_PROFILE: notarytool keychain profile name
# Optional env vars:
#   PROJECT_PATH (default: cocoaModem 2.0/cocoaModem 2.0.xcodeproj)
#   TARGET_NAME (default: cocoaModem 2.0)
#   CONFIGURATION (default: Release)
#   APP_NAME (default: cocoaModem 2.1rc6.app)
#   BUNDLE_OUTPUT_DIR (default: Builds/Release)
#   ZIP_OUTPUT_DIR (default: Releases)

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd xcodebuild
require_cmd codesign
require_cmd xcrun
require_cmd ditto
require_cmd plutil

: "${DEVELOPER_ID_APP:?Set DEVELOPER_ID_APP to your Developer ID Application identity}"
: "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE to your notarytool keychain profile name}"

PROJECT_PATH="${PROJECT_PATH:-cocoaModem 2.0/cocoaModem 2.0.xcodeproj}"
TARGET_NAME="${TARGET_NAME:-cocoaModem 2.0}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-cocoaModem 2.1rc6.app}"
BUNDLE_OUTPUT_DIR="${BUNDLE_OUTPUT_DIR:-Builds/Release}"
ZIP_OUTPUT_DIR="${ZIP_OUTPUT_DIR:-Releases}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_PATH="$BUNDLE_OUTPUT_DIR/$APP_NAME"
STAMP="$(date +%Y%m%d-%H%M%S)"
ZIP_PATH="$ZIP_OUTPUT_DIR/${APP_NAME%.app}-universal-${STAMP}.zip"

mkdir -p "$BUNDLE_OUTPUT_DIR" "$ZIP_OUTPUT_DIR"

echo "[1/6] Cleaning"
rm -rf "$APP_PATH"

echo "[2/6] Building universal Release app"
# Force both slices regardless of user defaults.
xcodebuild \
  -project "$PROJECT_PATH" \
  -target "$TARGET_NAME" \
  -configuration "$CONFIGURATION" \
  -arch x86_64 -arch arm64 \
  ONLY_ACTIVE_ARCH=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build did not produce expected app at: $APP_PATH" >&2
  exit 1
fi

EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist")"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"

if [[ ! -f "$EXECUTABLE_PATH" ]]; then
  echo "Expected executable not found at: $EXECUTABLE_PATH" >&2
  exit 1
fi

echo "[3/6] Signing app with Developer ID"
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "[4/6] Packaging app for notarization"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "[5/6] Submitting for notarization and waiting"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait

echo "[6/6] Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"

# Final validation for distribution policy.
if command -v syspolicy_check >/dev/null 2>&1; then
  echo "syspolicy_check distribution result:"
  syspolicy_check distribution "$APP_PATH" || true
fi

echo

echo "Done"
echo "App: $APP_PATH"
echo "Zip: $ZIP_PATH"
