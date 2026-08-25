#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK_ROOT=${ANDROID_SDK_ROOT:-"$HOME/Library/Android/sdk"}
SERIAL=${ANDROID_SERIAL:-emulator-5558}
case "$SERIAL" in
  emulator-5558)
    AVD_NAME=${MSA_AVD_NAME:-msa-gms-api36}
    WRITABLE_SYSTEM=${MSA_WRITABLE_SYSTEM:-0}
    ;;
  *)
    AVD_NAME=${MSA_AVD_NAME:-msa-api36}
    WRITABLE_SYSTEM=${MSA_WRITABLE_SYSTEM:-1}
    ;;
esac
OUTPUT_DIR=${1:-"$HOME/Applications"}
APP="$OUTPUT_DIR/MSA Emulator.app"

if [ "${MSA_SKIP_BUILD:-0}" != 1 ]; then
  "$ROOT/scripts/build-host.sh"
fi

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/msa-emulator-manager.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM
STAGED_APP="$TEMP_DIR/MSA Emulator.app"
CONTENTS="$STAGED_APP/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/work/.build/release/MSAHost" "$CONTENTS/MacOS/MSAHost"

PLIST="$CONTENTS/Info.plist"
plutil -create xml1 "$PLIST"
plutil -insert CFBundleDevelopmentRegion -string en "$PLIST"
plutil -insert CFBundleDisplayName -string "MSA Emulator" "$PLIST"
plutil -insert CFBundleExecutable -string MSAHost "$PLIST"
plutil -insert CFBundleIdentifier -string dev.msa.emulator-manager "$PLIST"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$PLIST"
plutil -insert CFBundleName -string "MSA Emulator" "$PLIST"
plutil -insert CFBundlePackageType -string APPL "$PLIST"
plutil -insert CFBundleShortVersionString -string 0.1 "$PLIST"
plutil -insert CFBundleVersion -string "$(date +%Y%m%d%H%M%S)" "$PLIST"
plutil -insert LSMinimumSystemVersion -string 14.0 "$PLIST"
plutil -insert LSUIElement -bool YES "$PLIST"
plutil -insert NSHighResolutionCapable -bool YES "$PLIST"
plutil -insert MSAEmulatorManager -bool YES "$PLIST"
plutil -insert MSAEmulatorSerial -string "$SERIAL" "$PLIST"
plutil -insert MSAAVDName -string "$AVD_NAME" "$PLIST"
plutil -insert MSAAndroidSDKRoot -string "$SDK_ROOT" "$PLIST"
if [ "$WRITABLE_SYSTEM" = 1 ]; then
  plutil -insert MSAWritableSystem -bool YES "$PLIST"
else
  plutil -insert MSAWritableSystem -bool NO "$PLIST"
fi

GENERIC_ICON="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns"
if [ -f "$GENERIC_ICON" ]; then
  cp "$GENERIC_ICON" "$CONTENTS/Resources/AppIcon.icns"
  plutil -insert CFBundleIconFile -string AppIcon "$PLIST"
fi

codesign --force --deep --sign - "$STAGED_APP" >/dev/null
mkdir -p "$OUTPUT_DIR"
if [ -e "$APP" ]; then
  PREVIOUS_APP="$TEMP_DIR/previous.app"
  mv "$APP" "$PREVIOUS_APP"
fi
if ! mv "$STAGED_APP" "$APP"; then
  if [ -n "${PREVIOUS_APP:-}" ] && [ -e "$PREVIOUS_APP" ]; then
    mv "$PREVIOUS_APP" "$APP"
  fi
  exit 1
fi

echo "Created: $APP"
echo "Emulator: $AVD_NAME ($SERIAL)"
echo "Open the app to start the emulator and keep its menu bar controls available."