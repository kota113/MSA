#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APK="$ROOT/android-agent/build/outputs/apk/release/MsaAgent-platform.apk"
OVERLAY="$ROOT/android-agent/build/outputs/overlay/MsaAutomotiveProjectionOverlay.apk"
OUTPUT="$ROOT/work/MsaAgent-magisk.zip"
MODULE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/msa-magisk.XXXXXX")
trap 'rm -rf "$MODULE_ROOT"' EXIT HUP INT TERM

"$ROOT/scripts/build-agent.sh"
"$ROOT/scripts/build-automotive-overlay.sh"

mkdir -p \
  "$MODULE_ROOT/system/priv-app/MsaAgent" \
  "$MODULE_ROOT/system/product/overlay" \
  "$MODULE_ROOT/system/etc/permissions"
cp "$ROOT/android-agent/magisk/module.prop" "$MODULE_ROOT/module.prop"
cp "$APK" "$MODULE_ROOT/system/priv-app/MsaAgent/MsaAgent.apk"
cp "$OVERLAY" "$MODULE_ROOT/system/product/overlay/MsaAutomotiveProjectionOverlay.apk"
cp "$ROOT/android-agent/privapp-permissions-msa.xml" \
  "$MODULE_ROOT/system/etc/permissions/privapp-permissions-msa.xml"

mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT"
(
  cd "$MODULE_ROOT"
  COPYFILE_DISABLE=1 zip -q -r "$OUTPUT" .
)

echo "Built: $OUTPUT"
