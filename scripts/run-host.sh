#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PACKAGE=${1:-com.android.settings}
if [ ! -x "$ROOT/work/.build/release/MSAHost" ]; then
  "$ROOT/scripts/build-host.sh"
fi
exec "$ROOT/work/.build/release/MSAHost" --package "$PACKAGE"
