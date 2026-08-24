#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /absolute/path/to/aosp"
  exit 2
fi
AOSP_ROOT=$1
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
EXPECTED="$AOSP_ROOT/vendor/macwsa"
if [[ ! -e "$EXPECTED" ]]; then
  echo "Place or symlink this repository at $EXPECTED first."
  echo "Example: ln -s '$PROJECT_ROOT' '$EXPECTED'"
  exit 2
fi
cd "$AOSP_ROOT"
source build/envsetup.sh
lunch macwsa_arm64-userdebug
m MacWsaAgent
m
