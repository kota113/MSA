#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$ROOT/work/module-cache"
cd "$ROOT"
CLANG_MODULE_CACHE_PATH="$ROOT/work/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/work/module-cache" \
swift build -c release --disable-sandbox --scratch-path "$ROOT/work/.build"
echo "Built: $ROOT/work/.build/release/MSAHost"
