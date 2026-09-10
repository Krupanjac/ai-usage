#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
swift build -c "$configuration"
bin_path="$(swift build -c "$configuration" --show-bin-path)"
app_path="$PWD/build/AIUsage.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
bash scripts/build-icon.sh
cp "$bin_path/AIUsage" "$app_path/Contents/MacOS/AIUsage"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
if [[ -n "${AIUSAGE_VERSION:-}" ]]; then
    [[ "$AIUSAGE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid app version.\n' >&2; exit 1; }
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $AIUSAGE_VERSION" "$app_path/Contents/Info.plist"
fi
if [[ -n "${AIUSAGE_BUILD_NUMBER:-}" ]]; then
    [[ "$AIUSAGE_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { printf 'Invalid build number.\n' >&2; exit 1; }
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $AIUSAGE_BUILD_NUMBER" "$app_path/Contents/Info.plist"
fi
cp build/assets/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$app_path/Contents/PkgInfo"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
printf 'Built %s\n' "$app_path"
