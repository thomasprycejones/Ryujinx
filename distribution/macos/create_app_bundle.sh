#!/bin/bash

# Terminate the script if any command returns a non-zero status
set -e

# Check if the correct number of arguments were supplied
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <PUBLISH_DIRECTORY> <OUTPUT_DIRECTORY> <ENTITLEMENTS_FILE_PATH>"
    exit 1
fi

PUBLISH_DIRECTORY=$(readlink -f "$1")
OUTPUT_DIRECTORY=$(readlink -f "$2")
ENTITLEMENTS_FILE_PATH=$(readlink -f "$3")

APP_BUNDLE_DIRECTORY="$OUTPUT_DIRECTORY/Ryujinx.app"

# Create the directories for the .app bundle
mkdir -p "$APP_BUNDLE_DIRECTORY/Contents" \
         "$APP_BUNDLE_DIRECTORY/Contents/Frameworks" \
         "$APP_BUNDLE_DIRECTORY/Contents/MacOS" \
         "$APP_BUNDLE_DIRECTORY/Contents/Resources"

# Copy executables
cp "$PUBLISH_DIRECTORY/Ryujinx.Ava" "$APP_BUNDLE_DIRECTORY/Contents/MacOS/Ryujinx"
chmod u+x "$APP_BUNDLE_DIRECTORY/Contents/MacOS/Ryujinx"

# Copy all libraries
cp "$PUBLISH_DIRECTORY"/*.dylib "$APP_BUNDLE_DIRECTORY/Contents/Frameworks"

# Copy resources
cp Info.plist "$APP_BUNDLE_DIRECTORY/Contents"
cp Ryujinx.icns "$APP_BUNDLE_DIRECTORY/Contents/Resources/Ryujinx.icns"
cp updater.sh "$APP_BUNDLE_DIRECTORY/Contents/Resources/updater.sh"
cp -r "$PUBLISH_DIRECTORY/THIRDPARTY.md" "$APP_BUNDLE_DIRECTORY/Contents/Resources"

# Write PkgInfo
echo -n "APPL????" > "$APP_BUNDLE_DIRECTORY/Contents/PkgInfo"

# Fixup libraries and executable
if ! python3 bundle_fix_up.py "$APP_BUNDLE_DIRECTORY" MacOS/Ryujinx; then
    echo "Failed to fix up libraries and executable. Exiting."
    exit 1
fi

# Check for codesign and rcodesign
if command -v codesign >/dev/null 2>&1; then
    echo "Using codesign for ad-hoc signing"
    codesign --entitlements "$ENTITLEMENTS_FILE_PATH" -f --deep -s - "$APP_BUNDLE_DIRECTORY"
elif command -v rcodesign >/dev/null 2>&1; then
    echo "Using rcodesign for ad-hoc signing"
    rcodesign sign --entitlements-xml-path "$ENTITLEMENTS_FILE_PATH" "$APP_BUNDLE_DIRECTORY"
else
    echo "Cannot find codesign or rcodesign on your system. Please install one of them."
    exit 1
fi