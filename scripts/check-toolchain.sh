#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"
swift_version=$(swift --version)
swift_components=$(printf '%s\n' "$swift_version" | sed -n 's/.*Swift version \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p' | head -n 1)

if [[ -z "$swift_components" ]]; then
    echo "Unable to determine the Swift compiler version." >&2
    exit 1
fi

read -r swift_major swift_minor <<< "$swift_components"
printf 'Swift compiler: %s\n' "$(printf '%s\n' "$swift_version" | head -n 1)"

if (( swift_major < 6 || (swift_major == 6 && swift_minor < 2) )); then
    echo "Swift 6.2 or newer is required." >&2
    exit 1
fi

if [[ "$mode" == "swift-only" ]]; then
    exit 0
fi

if [[ "$mode" != "all" ]]; then
    echo "Usage: $0 [all|swift-only]" >&2
    exit 2
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild is required for the full toolchain check." >&2
    exit 1
fi

xcode_version=$(xcodebuild -version)
xcode_components=$(printf '%s\n' "$xcode_version" | sed -n 's/^Xcode \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p' | head -n 1)
if [[ -z "$xcode_components" ]]; then
    echo "Unable to determine the Xcode version." >&2
    exit 1
fi

read -r xcode_major xcode_minor <<< "$xcode_components"
printf 'Xcode: %s\n' "$(printf '%s\n' "$xcode_version" | head -n 1)"

if (( xcode_major < 26 )); then
    echo "Xcode 26 or newer is required to build for macOS 26." >&2
    exit 1
fi
