#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
swift build -c "$configuration"
bin_path="$(swift build -c "$configuration" --show-bin-path)"
app_path="$PWD/build/AIUsage.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$bin_path/AIUsage" "$app_path/Contents/MacOS/AIUsage"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
printf 'APPL????' > "$app_path/Contents/PkgInfo"
codesign --force --sign - "$app_path"
printf 'Built %s\n' "$app_path"
