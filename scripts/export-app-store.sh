#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
ARCHIVE_PATH="$PWD/dist/AppStore/Paste Shifter $VERSION ($BUILD).xcarchive"
EXPORT_PATH="$PWD/dist/AppStore/Export $VERSION ($BUILD)"

[[ -d "$ARCHIVE_PATH" ]] || { print -u2 "Archive not found: $ARCHIVE_PATH"; exit 1; }
if [[ -e "$EXPORT_PATH" ]]; then
    print -u2 "Export folder already exists: $EXPORT_PATH"
    exit 1
fi

STAGE_PATH=$(mktemp -d "$PWD/dist/AppStore/.export.XXXXXX")
LOG_MARKER=$(mktemp "$PWD/.build/AppStoreExportMarker.XXXXXX")
touch "$LOG_MARKER"
trap 'rm -rf "$STAGE_PATH"; rm -f "$LOG_MARKER"' EXIT
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$STAGE_PATH" \
    -exportOptionsPlist Store/ExportOptions.plist \
    -allowProvisioningUpdates

rm -f "$STAGE_PATH/Packaging.log" "$STAGE_PATH/AppStoreInfo.plist"
for log_bundle in "$TMPDIR"/PasteShifter_*.xcdistributionlogs; do
    if [[ -d "$log_bundle" && "$log_bundle" -nt "$LOG_MARKER" ]]; then
        rm -rf "$log_bundle"
    fi
done
mv "$STAGE_PATH" "$EXPORT_PATH"
print "Mac App Store export ready: $EXPORT_PATH"
