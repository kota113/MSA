#!/bin/sh
set -eu

ADB=${ADB:-adb}
PACKAGE=dev.msa.agent
PROFILE=android.app.role.COMPANION_DEVICE_APP_STREAMING

"$ADB" wait-for-device
if ! "$ADB" shell pm path "$PACKAGE" >/dev/null 2>&1; then
  echo "$PACKAGE is not installed. Boot the msa_arm64 AOSP image."
  exit 1
fi

if ! "$ADB" shell cmd companiondevice list 0 | grep -q "$PACKAGE"; then
  "$ADB" shell cmd companiondevice associate 0 "$PACKAGE" 02:00:00:57:53:41 "$PROFILE" false
fi
"$ADB" shell cmd role add-role-holder --user 0 "$PROFILE" "$PACKAGE" 0 || true
"$ADB" shell cmd companiondevice list 0
"$ADB" shell dumpsys package "$PACKAGE" | grep -E 'CREATE_VIRTUAL_DEVICE|REQUEST_COMPANION_PROFILE_APP_STREAMING' || true
echo "Provisioning complete. Reboot once so the boot receiver starts the agent."
"$ADB" reboot
"$ADB" wait-for-device
