#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK_ROOT=${ANDROID_SDK_ROOT:-/Users/kota113/Library/Android/sdk}
SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/avdmanager"
PACKAGE="system-images;android-36.1;google_apis_playstore;arm64-v8a"
SOURCE_IMAGE="$SDK_ROOT/system-images/android-36.1/google_apis_playstore/arm64-v8a"
PRIVATE_IMAGE="$SDK_ROOT/system-images/android-36.1/macwsa_google_apis_playstore/arm64-v8a"
VERSION_LINK="$SDK_ROOT/system-images/android-36/macwsa_google_apis_playstore/arm64-v8a"
AVD_NAME=macwsa-gms-api36
AVD_CONFIG="$HOME/.android/avd/$AVD_NAME.avd/config.ini"
ROOTAVD_DIR="$ROOT/work/rootAVD-gms"
ROOTAVD_COMMIT=92df40eafa2f117053f56015e3c32ca706a55fa9

if [ ! -d "$SOURCE_IMAGE" ]; then
  yes | "$SDKMANAGER" --licenses >/dev/null || true
  "$SDKMANAGER" "$PACKAGE"
fi

if ! "$SDK_ROOT/emulator/emulator" -list-avds | grep -qx "$AVD_NAME"; then
  echo no | "$AVDMANAGER" create avd --force --name "$AVD_NAME" --package "$PACKAGE"
fi

if [ ! -d "$PRIVATE_IMAGE" ]; then
  mkdir -p "$(dirname "$PRIVATE_IMAGE")"
  if cp -cR "$SOURCE_IMAGE" "$PRIVATE_IMAGE" 2>/dev/null; then
    echo "Created an APFS copy-on-write system image."
  else
    cp -R "$SOURCE_IMAGE" "$PRIVATE_IMAGE"
    echo "Created a full private system image copy."
  fi
fi

if [ ! -f "$AVD_CONFIG" ]; then
  echo "Missing AVD config: $AVD_CONFIG" >&2
  exit 1
fi
CONFIG_TMP=$(mktemp "${TMPDIR:-/tmp}/macwsa-avd-config.XXXXXX")
trap 'rm -f "$CONFIG_TMP"' EXIT HUP INT TERM
awk '
  /^image\.sysdir\.1=/ {
    print "image.sysdir.1=system-images/android-36.1/macwsa_google_apis_playstore/arm64-v8a/"
    next
  }
  { print }
' "$AVD_CONFIG" > "$CONFIG_TMP"
cp "$CONFIG_TMP" "$AVD_CONFIG"

mkdir -p "$(dirname "$VERSION_LINK")"
if [ ! -e "$VERSION_LINK" ]; then
  ln -s "$PRIVATE_IMAGE" "$VERSION_LINK"
fi

if [ ! -d "$ROOTAVD_DIR/.git" ]; then
  git clone https://github.com/galihlasahido/rootAVD.git "$ROOTAVD_DIR"
fi
git -C "$ROOTAVD_DIR" checkout "$ROOTAVD_COMMIT"
if git -C "$ROOTAVD_DIR" apply --check "$ROOT/patches/rootavd-macwsa.patch" 2>/dev/null; then
  git -C "$ROOTAVD_DIR" apply "$ROOT/patches/rootavd-macwsa.patch"
fi
mkdir -p "$ROOTAVD_DIR/Apps"

echo "Prepared $AVD_NAME with an isolated Google Play system image."
echo "Next: GMS_EMULATOR_WINDOW=1 scripts/start-gms-emulator.sh"
echo "Then: ANDROID_SERIAL=emulator-5558 scripts/root-gms-emulator.sh"
