#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK_ROOT=${ANDROID_SDK_ROOT:-"$HOME/Library/Android/sdk"}
ADB="$SDK_ROOT/platform-tools/adb"
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
REPLACE=0
if [ "${1:-}" = "--replace" ]; then
  REPLACE=1
  shift
fi
PACKAGE=${1:-}
REQUESTED_NAME=${2:-}
OUTPUT_DIR=${3:-"$HOME/Applications"}

if [ -z "$PACKAGE" ]; then
  echo "Usage: $0 [--replace] <android-package> [display-name] [output-directory]" >&2
  exit 2
fi
if [ ! -x "$ADB" ]; then
  echo "adb not found: $ADB" >&2
  exit 1
fi

AAPT2=$(find "$SDK_ROOT/build-tools" -type f -name aapt2 | sort | tail -1)
if [ ! -x "$AAPT2" ]; then
  echo "aapt2 not found under $SDK_ROOT/build-tools" >&2
  exit 1
fi

APK_DEVICE_PATH=$(
  "$ADB" -s "$SERIAL" shell pm path "$PACKAGE" 2>/dev/null |
    sed -n '1s/^package://p' | tr -d '\r'
)
if [ -z "$APK_DEVICE_PATH" ]; then
  echo "$PACKAGE is not installed on $SERIAL" >&2
  exit 1
fi

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/msa-app.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM
APK="$TEMP_DIR/base.apk"
"$ADB" -s "$SERIAL" pull "$APK_DEVICE_PATH" "$APK" >/dev/null
BADGING=$($AAPT2 dump badging "$APK")

DETECTED_NAME=$(printf '%s\n' "$BADGING" | sed -n "s/^application-label:'\(.*\)'$/\1/p" | head -1)
DISPLAY_NAME=${REQUESTED_NAME:-$DETECTED_NAME}
DISPLAY_NAME=${DISPLAY_NAME:-$PACKAGE}
FILE_NAME=$(printf '%s' "$DISPLAY_NAME" | tr '/:' '--')
APP="$OUTPUT_DIR/$FILE_NAME.app"

if [ -e "$APP" ] && [ "$REPLACE" -eq 0 ]; then
  echo "Already exists: $APP" >&2
  echo "Use --replace, or choose another display name/output directory." >&2
  exit 1
fi

"$ROOT/scripts/build-host.sh"
MSA_SKIP_BUILD=1 "$ROOT/scripts/create-emulator-manager-app.sh" "$OUTPUT_DIR"

STAGED_APP="$TEMP_DIR/$FILE_NAME.app"
CONTENTS="$STAGED_APP/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/work/.build/release/MSAAppHost" "$CONTENTS/MacOS/MSAAppHost"

PLIST="$CONTENTS/Info.plist"
plutil -create xml1 "$PLIST"
plutil -insert CFBundleDevelopmentRegion -string en "$PLIST"
plutil -insert CFBundleDisplayName -string "$DISPLAY_NAME" "$PLIST"
plutil -insert CFBundleExecutable -string MSAAppHost "$PLIST"
BUNDLE_SUFFIX=$(printf '%s' "$PACKAGE" | tr '_' '-')
plutil -insert CFBundleIdentifier -string "dev.msa.android.$BUNDLE_SUFFIX" "$PLIST"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$PLIST"
plutil -insert CFBundleName -string "$DISPLAY_NAME" "$PLIST"
plutil -insert CFBundlePackageType -string APPL "$PLIST"
plutil -insert CFBundleShortVersionString -string 0.1 "$PLIST"
BUNDLE_VERSION=$(date +%Y%m%d%H%M%S)
plutil -insert CFBundleVersion -string "$BUNDLE_VERSION" "$PLIST"
plutil -insert LSMinimumSystemVersion -string 14.0 "$PLIST"
plutil -insert NSHighResolutionCapable -bool YES "$PLIST"
plutil -insert MSAPackageName -string "$PACKAGE" "$PLIST"
plutil -insert MSADisplayName -string "$DISPLAY_NAME" "$PLIST"
plutil -insert MSAEmulatorSerial -string "$SERIAL" "$PLIST"
plutil -insert MSAAVDName -string "$AVD_NAME" "$PLIST"
plutil -insert MSAAndroidSDKRoot -string "$SDK_ROOT" "$PLIST"
if [ "$WRITABLE_SYSTEM" = 1 ]; then
  plutil -insert MSAWritableSystem -bool YES "$PLIST"
else
  plutil -insert MSAWritableSystem -bool NO "$PLIST"
fi

ICON_CREATED=0
ICON_URI="content://dev.msa.agent.icons/icon/$PACKAGE"
if "$ADB" -s "$SERIAL" exec-out content read --uri "$ICON_URI" \
    >"$TEMP_DIR/source-icon" 2>/dev/null && \
    sips -s format png "$TEMP_DIR/source-icon" --out "$TEMP_DIR/source-icon.png" >/dev/null 2>&1; then
  ICON_CREATED=1
else
  ICON_RESOURCE=$(printf '%s\n' "$BADGING" |
    sed -n "s/^application-icon-[0-9][0-9]*:'\(.*\)'$/\1/p" | tail -1)
  if [ -n "$ICON_RESOURCE" ]; then
    unzip -p "$APK" "$ICON_RESOURCE" >"$TEMP_DIR/source-icon" 2>/dev/null || true
  fi
  if sips -s format png "$TEMP_DIR/source-icon" --out "$TEMP_DIR/source-icon.png" >/dev/null 2>&1; then
    ICON_CREATED=1
  fi
fi
if [ "$ICON_CREATED" -eq 1 ]; then
  ICONSET="$TEMP_DIR/AppIcon.iconset"
  mkdir -p "$ICONSET"
  sips -z 16 16 "$TEMP_DIR/source-icon.png" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$TEMP_DIR/source-icon.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$TEMP_DIR/source-icon.png" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$TEMP_DIR/source-icon.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$TEMP_DIR/source-icon.png" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$TEMP_DIR/source-icon.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$TEMP_DIR/source-icon.png" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$TEMP_DIR/source-icon.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$TEMP_DIR/source-icon.png" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$TEMP_DIR/source-icon.png" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  if iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns" 2>/dev/null; then
    plutil -insert CFBundleIconFile -string AppIcon "$PLIST"
  else
    ICON_CREATED=0
  fi
fi
if [ "$ICON_CREATED" -eq 0 ]; then
  GENERIC_ICON="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns"
  if [ -f "$GENERIC_ICON" ]; then
    cp "$GENERIC_ICON" "$CONTENTS/Resources/AppIcon.icns"
    plutil -insert CFBundleIconFile -string AppIcon "$PLIST"
  fi
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
echo "Android package: $PACKAGE"
echo "Emulator: $AVD_NAME ($SERIAL)"
echo "Open the app to start the emulator automatically when needed."
