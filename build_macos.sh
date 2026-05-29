#!/bin/bash

# Exit on error
set -e

# Change directory to the script's directory (project root)
cd "$(dirname "$0")"

APP_NAME="Pod"
RELEASE_DIR="build/macos/Build/Products/Release"
APP_BUNDLE="${RELEASE_DIR}/${APP_NAME}.app"
DMG_OUTPUT="${RELEASE_DIR}/Pod.dmg"
STAGING_DIR="${RELEASE_DIR}/dmg_staging"

echo "========================================="
echo " 📦 Packaging Pod into DMG (macOS)       "
echo "========================================="

echo ""
echo "Step 1: Building Flutter macOS app in Release mode..."
flutter build macos --release

# Fallback check
if [ ! -d "${APP_BUNDLE}" ]; then
  if [ -d "${RELEASE_DIR}/pod.app" ]; then
    APP_NAME="pod"
    APP_BUNDLE="${RELEASE_DIR}/${APP_NAME}.app"
  else
    echo "❌ Error: Could not find build/.app bundle at ${RELEASE_DIR}."
    exit 1
  fi
fi

echo ""
echo "Step 2: Ad-hoc code signing (allows opening on Apple Silicon without Developer account)..."
codesign --deep --force --sign - "${APP_BUNDLE}"
echo "✓ Ad-hoc signing complete"

echo ""
echo "Step 3: Preparing clean staging directory (app bundle only)..."
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"

echo ""
echo "Step 4: Removing old DMG (if exists)..."
rm -f "${DMG_OUTPUT}"

echo ""
echo "Step 5: Creating fancy DMG with create-dmg..."

# Background image is 1440x900 pixels
# On Retina (2x): 1440px = 720 logical points → window-size 720x450 fills perfectly
# On non-Retina (1x): image larger than window, Finder clips to window → still fills
#
# Icon positions (in logical points):
#   Pod.app:      left-center  x=190, y=240
#   Applications: right-center x=530, y=240
create-dmg \
  --volname "Pod" \
  --window-pos 200 120 \
  --window-size 540 380 \
  --icon-size 110 \
  --text-size 14 \
  --icon "${APP_NAME}.app" 135 190 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 405 190 \
  --hdiutil-quiet \
  "${DMG_OUTPUT}" \
  "${STAGING_DIR}/"

echo ""
echo "Step 6: Cleaning up staging directory..."
rm -rf "${STAGING_DIR}"

echo ""
echo "========================================="
echo " 🎉 DMG Created Successfully!"
echo " Path: ${DMG_OUTPUT}"
echo "========================================="
