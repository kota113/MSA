#!/bin/sh
set -eu

SDK_ROOT=${ANDROID_SDK_ROOT:-"$HOME/Library/Android/sdk"}
if [ "${GMS_EMULATOR_WINDOW:-0}" = 1 ]; then
  exec "$SDK_ROOT/emulator/emulator" \
    -avd msa-gms-api36 -port 5558 -no-snapshot -no-boot-anim -gpu host "$@"
else
  exec "$SDK_ROOT/emulator/emulator" \
    -avd msa-gms-api36 -port 5558 -no-window -no-snapshot -no-boot-anim -gpu host "$@"
fi
