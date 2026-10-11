#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
XCODE_DERIVED_DATA="$PWD/.build/XcodeDerivedData"
XCODE_ARGS=(
    -project PasteShifter.xcodeproj
    -scheme PasteShifter
    -configuration Release
    -destination 'generic/platform=macOS'
    -derivedDataPath "$XCODE_DERIVED_DATA"
    -allowProvisioningUpdates
)
if [[ "${PASTE_SHIFTER_REGISTER_DEVICE:-0}" == "1" ]]; then
    XCODE_ARGS+=( -allowProvisioningDeviceRegistration )
fi
XCODE_ARGS+=( build )
xcodebuild "${XCODE_ARGS[@]}"
APP="$PWD/dist/Paste Shifter.app"
BUILT_APP="$XCODE_DERIVED_DATA/Build/Products/Release/Paste Shifter.app"
STAGING_ROOT=$(mktemp -d "$PWD/.build/package.XXXXXX")
trap 'rm -rf "$STAGING_ROOT"' EXIT
STAGED_APP="$STAGING_ROOT/Paste Shifter.app"
mkdir -p "$PWD/dist"
ditto "$BUILT_APP" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
# Never truncate or re-sign a running executable in place.
if [[ -d "$APP" ]]; then
    mv "$APP" "$STAGING_ROOT/Previous.app"
fi
if ! mv "$STAGED_APP" "$APP"; then
    [[ ! -d "$STAGING_ROOT/Previous.app" ]] || mv "$STAGING_ROOT/Previous.app" "$APP"
    exit 1
fi
print "App lista: $APP"
