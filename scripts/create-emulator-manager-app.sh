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
cp "$ROOT/work/.build/release/MSAEmulatorManager" "$CONTENTS/MacOS/MSAEmulatorManager"
cp "$ROOT/work/.build/release/MSAAppHost" "$CONTENTS/Resources/MSAAppHost"
cp "$ROOT/macos-host/Resources/MSAMenuBarIcon.png" "$CONTENTS/Resources/MSAMenuBarIcon.png"

PLIST="$CONTENTS/Info.plist"
plutil -create xml1 "$PLIST"
plutil -insert CFBundleDevelopmentRegion -string en "$PLIST"
plutil -insert CFBundleDisplayName -string "MSA Emulator" "$PLIST"
plutil -insert CFBundleExecutable -string MSAEmulatorManager "$PLIST"
plutil -insert CFBundleIdentifier -string dev.msa.emulator-manager "$PLIST"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$PLIST"
plutil -insert CFBundleName -string "MSA Emulator" "$PLIST"
plutil -insert CFBundlePackageType -string APPL "$PLIST"
plutil -insert CFBundleShortVersionString -string 0.1 "$PLIST"
plutil -insert CFBundleVersion -string "$(date +%Y%m%d%H%M%S)" "$PLIST"
plutil -insert LSMinimumSystemVersion -string 14.0 "$PLIST"
plutil -insert LSUIElement -bool YES "$PLIST"
plutil -insert NSHighResolutionCapable -bool YES "$PLIST"
plutil -insert NSCameraUsageDescription -string "MSA Emulator uses the selected camera for Android apps." "$PLIST"
plutil -insert NSMicrophoneUsageDescription -string "MSA Emulator uses the selected microphone for Android apps." "$PLIST"
plutil -insert NSLocationWhenInUseUsageDescription -string "MSA Emulator shares this Mac's location with Android apps." "$PLIST"
plutil -insert MSAEmulatorSerial -string "$SERIAL" "$PLIST"
plutil -insert MSAAVDName -string "$AVD_NAME" "$PLIST"
plutil -insert MSAAndroidSDKRoot -string "$SDK_ROOT" "$PLIST"
if [ "$WRITABLE_SYSTEM" = 1 ]; then
  plutil -insert MSAWritableSystem -bool YES "$PLIST"
else
  plutil -insert MSAWritableSystem -bool NO "$PLIST"
fi

ICON_SOURCE="$ROOT/macos-host/Resources/MSAAppIcon.png"
ICONSET="$TEMP_DIR/AppIcon.iconset"
ICON_MASTER="$TEMP_DIR/AppIcon.png"
mkdir -p "$ICONSET"
sips -Z 1024 "$ICON_SOURCE" --out "$ICON_MASTER" >/dev/null
sips -p 1024 1024 "$ICON_MASTER" --out "$ICON_MASTER" >/dev/null
sips -z 16 16 "$ICON_MASTER" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_MASTER" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_MASTER" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_MASTER" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_MASTER" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_MASTER" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_MASTER" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_MASTER" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
plutil -insert CFBundleIconFile -string AppIcon "$PLIST"

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