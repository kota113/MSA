#!/bin/sh
set -eu
ADB=${ADB:-adb}
SERIAL=${ANDROID_SERIAL:-emulator-5556}
"$ADB" -s "$SERIAL" forward --remove tcp:27183 >/dev/null 2>&1 || true
"$ADB" -s "$SERIAL" forward tcp:27183 tcp:27183
echo "127.0.0.1:27183 -> emulator:27183"
