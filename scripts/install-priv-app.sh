#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK_ROOT=${ANDROID_SDK_ROOT:-"$HOME/Library/Android/sdk"}
ADB=${ADB:-$SDK_ROOT/platform-tools/adb}
SERIAL=${ANDROID_SERIAL:-emulator-5556}
APKSIGNER="$SDK_ROOT/build-tools/36.0.0/apksigner"
APK="$ROOT/android-agent/build/outputs/apk/release/MsaAgent-platform.apk"
REMOTE_DIR=/system/priv-app/MsaAgent
PERMISSIONS_REMOTE=/system/etc/permissions/privapp-permissions-msa.xml
PACKAGE=dev.msa.agent
PROFILE=android.app.role.COMPANION_DEVICE_APP_STREAMING

adb_cmd() {
  "$ADB" -s "$SERIAL" "$@"
}

wait_boot() {
  adb_cmd wait-for-device
  i=0
  while [ "$(adb_cmd shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != 1 ]; do
    i=$((i + 1))
    [ "$i" -lt 180 ] || { echo "Timed out waiting for Android boot"; exit 1; }
    sleep 1
  done
}

if [ ! -s "$APK" ]; then
  "$ROOT/scripts/build-agent.sh"
fi

wait_boot
adb_cmd root
adb_cmd wait-for-device
adb_cmd remount -R || true
adb_cmd wait-for-device
adb_cmd root
adb_cmd wait-for-device
adb_cmd remount

FRAMEWORK_APK="$ROOT/work/framework-res.apk"
adb_cmd pull /system/framework/framework-res.apk "$FRAMEWORK_APK" >/dev/null
echo "Image platform certificate:"
"$APKSIGNER" verify --print-certs "$FRAMEWORK_APK" | sed -n '1,4p'
echo "Agent certificate:"
"$APKSIGNER" verify --print-certs "$APK" | sed -n '1,4p'

adb_cmd shell mkdir -p "$REMOTE_DIR"
adb_cmd push "$ROOT/android-agent/privapp-permissions-msa.xml" "$PERMISSIONS_REMOTE"
adb_cmd shell chmod 0644 "$PERMISSIONS_REMOTE"
adb_cmd shell restorecon "$PERMISSIONS_REMOTE"
adb_cmd push "$APK" "$REMOTE_DIR/MsaAgent.apk"
adb_cmd shell chmod 0644 "$REMOTE_DIR/MsaAgent.apk"
adb_cmd shell restorecon -RF "$REMOTE_DIR"
adb_cmd reboot
wait_boot

adb_cmd shell settings put global hidden_api_policy 1 || true
if ! adb_cmd shell cmd companiondevice list 0 | grep -q "$PACKAGE"; then
  adb_cmd shell cmd companiondevice associate 0 "$PACKAGE" 02:00:00:57:53:41 "$PROFILE" false
fi
adb_cmd shell cmd role add-role-holder --user 0 "$PROFILE" "$PACKAGE" 0
adb_cmd reboot
wait_boot
adb_cmd forward tcp:27183 tcp:27183

adb_cmd shell pm path "$PACKAGE"
adb_cmd shell cmd companiondevice list 0
adb_cmd shell dumpsys package "$PACKAGE" | grep -E 'CREATE_VIRTUAL_DEVICE|REQUEST_COMPANION_PROFILE_APP_STREAMING' || true
echo "MsaAgent privileged installation complete."
