#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK_ROOT=${ANDROID_SDK_ROOT:-"$HOME/Library/Android/sdk"}
BUILD_TOOLS="$SDK_ROOT/build-tools/36.0.0"
AAPT2="$BUILD_TOOLS/aapt2"
APKSIGNER="$BUILD_TOOLS/apksigner"
ANDROID_JAR="$SDK_ROOT/platforms/android-36/android.jar"
SOURCE="$ROOT/android-agent/automotive-overlay"
OUTPUT_DIR="$ROOT/android-agent/build/outputs/overlay"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/macwsa-overlay.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

mkdir -p "$OUTPUT_DIR"
"$AAPT2" compile --dir "$SOURCE/res" -o "$TEMP_DIR/resources.zip"
"$AAPT2" link \
  -o "$TEMP_DIR/MacWsaAutomotiveProjectionOverlay-unsigned.apk" \
  --manifest "$SOURCE/AndroidManifest.xml" \
  --auto-add-overlay \
  -I "$ANDROID_JAR" \
  "$TEMP_DIR/resources.zip"
"$APKSIGNER" sign \
  --key "$ROOT/android-agent/test-keys/platform.pk8" \
  --cert "$ROOT/android-agent/test-keys/platform.x509.pem" \
  --out "$OUTPUT_DIR/MacWsaAutomotiveProjectionOverlay.apk" \
  "$TEMP_DIR/MacWsaAutomotiveProjectionOverlay-unsigned.apk"
"$APKSIGNER" verify "$OUTPUT_DIR/MacWsaAutomotiveProjectionOverlay.apk"
echo "Built: $OUTPUT_DIR/MacWsaAutomotiveProjectionOverlay.apk"
