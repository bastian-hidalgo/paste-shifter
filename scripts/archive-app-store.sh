#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
ARCHIVE_DIR="$PWD/dist/AppStore"
ARCHIVE_PATH="$ARCHIVE_DIR/Paste Shifter $VERSION ($BUILD).xcarchive"
DERIVED_DATA="$PWD/.build/AppStoreDerivedData"
CLANG_MODULE_CACHE_PATH="$PWD/.build/AppStoreClangModuleCache"
SWIFT_MODULE_CACHE_PATH="$PWD/.build/AppStoreSwiftModuleCache"

mkdir -p "$ARCHIVE_DIR"
if [[ -e "$ARCHIVE_PATH" ]]; then
    print -u2 "Archive already exists: $ARCHIVE_PATH"
    exit 1
fi

export CLANG_MODULE_CACHE_PATH SWIFT_MODULE_CACHE_PATH
xcodebuild \
    -project PasteShifter.xcodeproj \
    -scheme PasteShifter \
    -configuration AppStore \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive

codesign --verify --deep --strict "$ARCHIVE_PATH/Products/Applications/Paste Shifter.app"
print "Mac App Store archive ready: $ARCHIVE_PATH"
