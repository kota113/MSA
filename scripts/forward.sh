#!/bin/sh
set -eu
ADB=${ADB:-adb}
SERIAL=${ANDROID_SERIAL:-emulator-5556}
for PORT in 27183 27184; do
  "$ADB" -s "$SERIAL" forward --remove "tcp:$PORT" >/dev/null 2>&1 || true
  "$ADB" -s "$SERIAL" forward "tcp:$PORT" "tcp:$PORT"
  echo "127.0.0.1:$PORT -> emulator:$PORT"
done
