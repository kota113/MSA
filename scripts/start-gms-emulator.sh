#!/bin/sh
set -eu

SDK_ROOT=${ANDROID_SDK_ROOT:-"$HOME/Library/Android/sdk"}
AVD_NAME=${MSA_AVD_NAME:-msa-gms-api36}
if [ "${GMS_EMULATOR_WINDOW:-0}" = 1 ]; then
  exec "$SDK_ROOT/emulator/emulator" \
    -avd "$AVD_NAME" -port 5558 -no-snapshot -no-boot-anim -gpu host "$@"
else
  exec "$SDK_ROOT/emulator/emulator" \
    -avd "$AVD_NAME" -port 5558 -no-window -no-snapshot -no-boot-anim -gpu host "$@"
fi
