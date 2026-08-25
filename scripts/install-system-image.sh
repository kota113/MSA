#!/bin/sh
set -eu

SDK_ROOT=${ANDROID_SDK_ROOT:-"$HOME/Library/Android/sdk"}
SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/avdmanager"
PACKAGE="system-images;android-36;default;arm64-v8a"
AVD_NAME=msa-api36

yes | "$SDKMANAGER" --licenses >/dev/null || true
"$SDKMANAGER" "$PACKAGE"

if ! "$SDK_ROOT/emulator/emulator" -list-avds | grep -qx "$AVD_NAME"; then
  echo no | "$AVDMANAGER" create avd --force --name "$AVD_NAME" --package "$PACKAGE"
fi

echo "Installed AVD: $AVD_NAME"
