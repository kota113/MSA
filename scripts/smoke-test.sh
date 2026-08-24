#!/bin/sh
set -eu
ADB=${ADB:-adb}
SERIAL=${ANDROID_SERIAL:-emulator-5556}
PACKAGE=${1:-com.android.settings}

"$(dirname "$0")/forward.sh"
"$ADB" -s "$SERIAL" shell pidof dev.macwsa.agent >/dev/null
"$ADB" -s "$SERIAL" shell dumpsys companiondevice | grep -q dev.macwsa.agent
"$ADB" -s "$SERIAL" shell pm path "$PACKAGE" >/dev/null
echo "Agent, association, target package, and TCP forwarding are ready."
echo "Run: scripts/run-host.sh $PACKAGE"
