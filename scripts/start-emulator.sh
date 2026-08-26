#!/bin/sh
set -eu

SDK_ROOT=${ANDROID_SDK_ROOT:-"$HOME/Library/Android/sdk"}
exec "$SDK_ROOT/emulator/emulator" \
  -avd msa-api36 \
  -writable-system \
  -no-boot-anim \
  -gpu host \
  "$@"
