#!/bin/sh
set -eu

SDK_ROOT=${ANDROID_SDK_ROOT:-"$HOME/Library/Android/sdk"}
ADB=${ADB:-"$SDK_ROOT/platform-tools/adb"}
SERIAL=${ANDROID_SERIAL:-emulator-5558}
ACTION=${1:-}
ROLE=android.app.role.SYSTEM_AUTOMOTIVE_PROJECTION
AGENT=dev.msa.agent
ANDROID_AUTO=com.google.android.projection.gearhead
MODULE_DIR=/data/adb/modules/msa_agent/system/product/overlay
OVERLAY="$MODULE_DIR/MsaAutomotiveProjectionOverlay.apk"
DISABLED_OVERLAY="$OVERLAY.disabled"

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

has_holder() {
  adb_cmd shell cmd role get-role-holders --user 0 "$ROLE" | grep -q "^$1$"
}

case "$ACTION" in
  enable)
    if adb_cmd shell su -c "test -f $DISABLED_OVERLAY"; then
      adb_cmd shell su -c "mv $DISABLED_OVERLAY $OVERLAY"
    elif ! adb_cmd shell su -c "test -f $OVERLAY"; then
      echo "Secure capture overlay is missing; run scripts/install-gms-agent.sh first." >&2
      exit 1
    fi
    adb_cmd reboot
    wait_boot
    if has_holder "$AGENT"; then
      adb_cmd shell cmd role remove-role-holder --user 0 "$ROLE" "$AGENT" 0
    fi
    if has_holder "$ANDROID_AUTO"; then
      adb_cmd shell cmd role remove-role-holder --user 0 "$ROLE" "$ANDROID_AUTO" 0
    fi
    adb_cmd shell cmd role add-role-holder --user 0 "$ROLE" "$AGENT" 0
    ;;
  disable)
    if adb_cmd shell su -c "test -f $OVERLAY"; then
      adb_cmd shell su -c "mv $OVERLAY $DISABLED_OVERLAY"
    fi
    adb_cmd reboot
    wait_boot
    if has_holder "$AGENT"; then
      adb_cmd shell cmd role remove-role-holder --user 0 "$ROLE" "$AGENT" 0
    fi
    if ! has_holder "$ANDROID_AUTO"; then
      adb_cmd shell cmd role add-role-holder --user 0 "$ROLE" "$ANDROID_AUTO" 0
    fi
    ;;
  *)
    echo "Usage: $0 enable|disable" >&2
    exit 2
    ;;
esac

adb_cmd forward tcp:27183 tcp:27183
echo "Automotive projection holder:"
adb_cmd shell cmd role get-role-holders --user 0 "$ROLE"
echo "Automotive projection config:"
adb_cmd shell cmd overlay lookup android android:string/config_systemAutomotiveProjection
echo "Secure capture grant:"
adb_cmd shell dumpsys package "$AGENT" |
  sed -n '/install permissions:/,/User 0:/p' |
  grep 'CAPTURE_SECURE_VIDEO_OUTPUT' || echo "not granted"
