# build_ios_xcframework.sh
#  ClaritySync
# Created by Lynn Chu on 2026/2/12.

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/target/xcframework"
LIBNAME="df3_ios"

mkdir -p "$OUT"

# Rust iOS targets (Apple Silicon Mac)
rustup target add aarch64-apple-ios
rustup target add aarch64-apple-ios-sim

pushd "$ROOT" >/dev/null

cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim

DEVICE_LIB="$ROOT/target/aarch64-apple-ios/release/lib${LIBNAME}.a"
SIM_LIB="$ROOT/target/aarch64-apple-ios-sim/release/lib${LIBNAME}.a"

rm -rf "$OUT/${LIBNAME}.xcframework"

xcodebuild -create-xcframework \
  -library "$DEVICE_LIB" -headers "$ROOT/include" \
  -library "$SIM_LIB" -headers "$ROOT/include" \
  -output "$OUT/${LIBNAME}.xcframework"

popd >/dev/null

echo "Built: $OUT/${LIBNAME}.xcframework"
