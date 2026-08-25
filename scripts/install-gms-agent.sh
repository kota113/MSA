#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK_ROOT=${ANDROID_SDK_ROOT:-/Users/kota113/Library/Android/sdk}
ADB=${ADB:-$SDK_ROOT/platform-tools/adb}
SERIAL=${ANDROID_SERIAL:-emulator-5558}
MODULE="$ROOT/work/MacWsaAgent-magisk.zip"
REMOTE_MODULE=/data/local/tmp/MacWsaAgent-magisk.zip
PACKAGE=dev.macwsa.agent
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

"$ROOT/scripts/build-magisk-module.sh"
wait_boot
if ! adb_cmd shell su -c id | grep -q 'uid=0(root)'; then
  echo "Magisk root is not authorized for ADB shell." >&2
  echo "Open Magisk > Superuser and enable [SharedUID] Shell, then retry." >&2
  exit 1
fi
adb_cmd push "$MODULE" "$REMOTE_MODULE"
adb_cmd shell su -c "magisk --install-module $REMOTE_MODULE"
adb_cmd reboot
wait_boot

case "$(adb_cmd shell pm path "$PACKAGE" 2>/dev/null | head -n 1 | tr -d '\r')" in
  package:/data/app/*)
    echo "Removing an older data update so the Magisk-mounted priv-app is used."
    adb_cmd shell su -c "pm uninstall -k $PACKAGE"
    adb_cmd reboot
    wait_boot
    ;;
esac

adb_cmd shell su -c 'settings put global hidden_api_policy 1' || true
if ! adb_cmd shell cmd companiondevice list 0 | grep -q "$PACKAGE"; then
  adb_cmd shell cmd companiondevice associate 0 "$PACKAGE" 02:00:00:57:53:41 "$PROFILE" false
fi
adb_cmd shell cmd role set-bypassing-role-qualification true
if ! adb_cmd shell cmd role add-role-holder --user 0 "$PROFILE" "$PACKAGE" 0; then
  adb_cmd shell cmd role set-bypassing-role-qualification false
  exit 1
fi
adb_cmd shell cmd role set-bypassing-role-qualification false
adb_cmd reboot
wait_boot
adb_cmd forward tcp:27183 tcp:27183

adb_cmd shell pm path "$PACKAGE"
adb_cmd shell cmd companiondevice list 0
adb_cmd shell dumpsys package "$PACKAGE" | grep -E \
  'CREATE_VIRTUAL_DEVICE|REQUEST_COMPANION_PROFILE_APP_STREAMING|ADD_TRUSTED_DISPLAY' || true
echo "MacWsaAgent Magisk module installation complete on $SERIAL."
