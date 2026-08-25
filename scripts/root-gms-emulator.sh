#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK_ROOT=${ANDROID_SDK_ROOT:-/Users/kota113/Library/Android/sdk}
SERIAL=${ANDROID_SERIAL:-emulator-5558}
ROOTAVD_DIR="$ROOT/work/rootAVD-gms"
RAMDISK=system-images/android-36/macwsa_google_apis_playstore/arm64-v8a/ramdisk.img

if [ ! -x "$ROOTAVD_DIR/rootAVD.sh" ]; then
  echo "Run scripts/setup-gms-avd.sh first." >&2
  exit 1
fi

"$SDK_ROOT/platform-tools/adb" -s "$SERIAL" wait-for-device
env \
  ANDROID_HOME="$SDK_ROOT" \
  ANDROID_SERIAL="$SERIAL" \
  PATH="$SDK_ROOT/platform-tools:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$ROOTAVD_DIR/rootAVD.sh" "$RAMDISK"

echo "rootAVD patched the isolated ramdisk and stopped the emulator."
echo "Start it once with GMS_EMULATOR_WINDOW=1, open Magisk, and accept additional setup."
