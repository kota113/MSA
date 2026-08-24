#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
STUB_DIR="$ROOT/android-agent/system-stubs"
KEY_DIR="$ROOT/android-agent/test-keys"
BRANCH=android16-qpr2-release
BASE=https://android.googlesource.com

mkdir -p "$STUB_DIR" "$KEY_DIR" "$ROOT/work/downloads"

fetch_gitiles_blob() {
  url=$1
  destination=$2
  encoded="$ROOT/work/downloads/$(basename "$destination").base64"
  curl --fail --location --retry 3 --user-agent MacWSA-PoC "$url?format=TEXT" --output "$encoded"
  base64 --decode --input "$encoded" --output "$destination"
  rm "$encoded"
}

if [ ! -s "$STUB_DIR/android.jar" ]; then
  fetch_gitiles_blob \
    "$BASE/platform/prebuilts/sdk/+/refs/heads/$BRANCH/36/system/android.jar" \
    "$STUB_DIR/android.jar"
fi

if [ ! -s "$KEY_DIR/platform.pk8" ]; then
  fetch_gitiles_blob \
    "$BASE/platform/build/+/refs/heads/$BRANCH/target/product/security/platform.pk8" \
    "$KEY_DIR/platform.pk8"
fi

if [ ! -s "$KEY_DIR/platform.x509.pem" ]; then
  fetch_gitiles_blob \
    "$BASE/platform/build/+/refs/heads/$BRANCH/target/product/security/platform.x509.pem" \
    "$KEY_DIR/platform.x509.pem"
fi

echo "Android 16 system API stub and AOSP test platform keys are ready."
