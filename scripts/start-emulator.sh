#!/bin/sh
set -eu

SDK_ROOT=${ANDROID_SDK_ROOT:-/Users/kota113/Library/Android/sdk}
exec "$SDK_ROOT/emulator/emulator" \
  -avd macwsa-api36 \
  -writable-system \
  -no-snapshot \
  -no-boot-anim \
  "$@"
