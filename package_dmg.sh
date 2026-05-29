#!/bin/bash

# Exit on error
set -e

# Change directory to the script's directory (project root)
cd "$(dirname "$0")"

APP_NAME="unclutter"
RELEASE_DIR="build/macos/Build/Products/Release"
APP_BUNDLE="${RELEASE_DIR}/${APP_NAME}.app"
DMG_NAME="build/macos/Build/Products/Release/unClutter.dmg"
TEMP_DIR="${RELEASE_DIR}/dmg_temp"

echo "========================================="
echo " 📦 Packaging unClutter into DMG (macOS) "
echo "========================================="

echo "Step 1: Building Flutter macOS app in Release mode..."
flutter build macos --release

if [ ! -d "${APP_BUNDLE}" ]; then
  # Fallback check if the app name matches the pubspec name (pod.app)
  if [ -d "${RELEASE_DIR}/pod.app" ]; then
    APP_NAME="pod"
    APP_BUNDLE="${RELEASE_DIR}/${APP_NAME}.app"
  else
    echo "❌ Error: Could not find build/.app bundle at ${RELEASE_DIR}."
    exit 1
  fi
fi

echo "Step 2: Preparing staging directories..."
rm -rf "${TEMP_DIR}"
mkdir -p "${TEMP_DIR}"
rm -f "${DMG_NAME}"

echo "Step 3: Copying application bundle..."
cp -R "${APP_BUNDLE}" "${TEMP_DIR}/"

echo "Step 4: Creating symlink to Applications directory..."
ln -s /Applications "${TEMP_DIR}/Applications"

echo "Step 5: Generating DMG file using hdiutil..."
hdiutil create -volname "unClutter" -srcfolder "${TEMP_DIR}" -ov -format UDZO "${DMG_NAME}"

echo "Step 6: Cleaning up temporary files..."
rm -rf "${TEMP_DIR}"

echo "========================================="
echo " 🎉 DMG Created Successfully!"
echo " Path: ${DMG_NAME}"
echo "========================================="
