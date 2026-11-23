#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export MACOSX_DEPLOYMENT_TARGET=27.0
T="aarch64-apple-darwin"
for t in $T; do cargo build --release --target $t; done
rm -rf build/TypstBridge.xcframework; mkdir -p build
args=()
for t in $T; do args+=(-library target/$t/release/libtypst_bridge.a -headers include); done
xcodebuild -create-xcframework "${args[@]}" -output build/TypstBridge.xcframework
