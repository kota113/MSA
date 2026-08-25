#!/bin/sh
set -eu

SDK_ROOT=${ANDROID_SDK_ROOT:-/Users/kota113/Library/Android/sdk}
if [ "${GMS_EMULATOR_WINDOW:-0}" = 1 ]; then
  exec "$SDK_ROOT/emulator/emulator" \
    -avd macwsa-gms-api36 -port 5558 -no-snapshot -no-boot-anim -gpu host "$@"
else
  exec "$SDK_ROOT/emulator/emulator" \
    -avd macwsa-gms-api36 -port 5558 -no-window -no-snapshot -no-boot-anim -gpu host "$@"
fi
