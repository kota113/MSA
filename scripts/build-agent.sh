#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK_ROOT=${ANDROID_SDK_ROOT:-/Users/kota113/Library/Android/sdk}
GRADLE=${GRADLE:-$ROOT/android-agent/gradlew}
APKSIGNER="$SDK_ROOT/build-tools/36.0.0/apksigner"

if [ ! -s "$ROOT/android-agent/system-stubs/android.jar" ]; then
  "$ROOT/scripts/fetch-android-prebuilts.sh"
fi

cd "$ROOT/android-agent"
"$GRADLE" --no-daemon assembleRelease

UNSIGNED="$ROOT/android-agent/build/outputs/apk/release/MacWsaAgent-release-unsigned.apk"
SIGNED="$ROOT/android-agent/build/outputs/apk/release/MacWsaAgent-platform.apk"
"$APKSIGNER" sign \
  --key "$ROOT/android-agent/test-keys/platform.pk8" \
  --cert "$ROOT/android-agent/test-keys/platform.x509.pem" \
  --out "$SIGNED" \
  "$UNSIGNED"
"$APKSIGNER" verify --verbose --print-certs "$SIGNED"
echo "Built: $SIGNED"
