#!/bin/bash
# Builds Typo.app from the command line: the Typst bridge when needed, the Xcode project, then the app.
#
#   ./build.sh            Release build into build/Typo.app
#   ./build.sh --debug    Debug build instead
#   ./build.sh --bridge   rebuild the Rust bridge even if it looks current
#   ./build.sh --test     also run the Swift package tests
#   ./build.sh --open     open the app when the build is done
set -euo pipefail
cd "$(dirname "$0")"

config=Release bridge=auto test=no open=no
for arg in "$@"; do
    case "$arg" in
        --debug) config=Debug ;;
        --bridge) bridge=yes ;;
        --test) test=yes ;;
        --open) open=yes ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (see --help)" >&2; exit 2 ;;
    esac
done

need() { command -v "$1" >/dev/null || { echo "Missing $1. $2" >&2; exit 1; }; }
need xcodebuild "Install Xcode 27 and run: sudo xcode-select -s /Applications/Xcode.app"
need xcodegen "Install it with: brew install xcodegen"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

xcframework=bridge/build/TypstBridge.xcframework
if [[ $bridge == auto ]]; then
    # Rebuild when the bridge is missing or its Rust sources changed since the last build.
    if [[ ! -d $xcframework ]] || [[ -n $(find bridge/src bridge/include bridge/Cargo.toml bridge/Cargo.lock -newer "$xcframework" -print -quit) ]]; then
        bridge=yes
    fi
fi
if [[ $bridge == yes ]]; then
    need cargo "Install Rust with: curl https://sh.rustup.rs -sSf | sh"
    step "Building the Typst bridge (the first build takes a few minutes)"
    bridge/build-xcframework.sh
fi

step "Generating Typo.xcodeproj"
xcodegen generate --quiet

if [[ $test == yes ]]; then
    step "Testing the Swift package"
    (cd Packages/Typo && swift test)
fi

step "Building Typo ($config)"
derived=build/DerivedData
log=build/xcodebuild.log
mkdir -p build
# Xcode keeps a copy of the bridge header and doesn't notice when the bridge changes it.
for d in "$derived"/Build/Products/*/include; do
    [[ -f $d/module.modulemap ]] && cp bridge/include/typst_bridge.h "$d/"
done
if ! xcodebuild -project Typo.xcodeproj -scheme Typo -configuration "$config" -derivedDataPath "$derived" build >"$log" 2>&1; then
    grep -E "error:|BUILD FAILED" "$log" | head -20 >&2
    echo "Build failed. Full log: $log" >&2
    exit 1
fi

# Xcode fills the String Catalog only when it builds in the IDE; this does the same from the command line.
stringsdata=$(find "$derived/Build/Intermediates.noindex/Typo.build/$config/Typo.build" -name '*.stringsdata' 2>/dev/null)
if [[ -n $stringsdata ]]; then
    args=(); while IFS= read -r f; do args+=(--stringsdata "$f"); done <<<"$stringsdata"
    xcrun xcstringstool sync App/Localizable.xcstrings "${args[@]}"
fi

rm -rf build/Typo.app
cp -R "$derived/Build/Products/$config/Typo.app" build/Typo.app
step "Done: build/Typo.app"

[[ $open == yes ]] && open build/Typo.app
exit 0
