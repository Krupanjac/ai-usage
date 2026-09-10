#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" != "--skip-build" ]]; then
    bash scripts/build-app.sh release
fi
app_path="$PWD/build/AIUsage.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
architecture="$(uname -m)"
volume_name="AIUsage $version"
output_path="$PWD/build/AIUsage-$version-$architecture.dmg"
work_dir="$(mktemp -d "$PWD/build/dmg.XXXXXX")"
mount_path=""
mounted=false
cleanup() {
    if [[ "$mounted" == true ]] && ! hdiutil detach "$mount_path" -quiet; then
        printf 'Could not eject %s; keeping the temporary image at %s.\n' "$mount_path" "$work_dir" >&2
        return
    fi
    rm -rf "$work_dir"
}
trap cleanup EXIT

mkdir -p "$work_dir/staging"
ditto "$app_path" "$work_dir/staging/AIUsage.app"
ln -s /Applications "$work_dir/staging/Applications"
cp Resources/Install.txt "$work_dir/staging/Install.txt"
touch "$work_dir/staging/.metadata_never_index"

hdiutil create -quiet -volname "$volume_name" -fs HFS+ -format UDRW \
    -srcfolder "$work_dir/staging" "$work_dir/writable.dmg"
hdiutil attach -noautoopen -readwrite -plist "$work_dir/writable.dmg" > "$work_dir/mount.plist"
entity=0
while /usr/libexec/PlistBuddy -c "Print :system-entities:$entity" "$work_dir/mount.plist" >/dev/null 2>&1; do
    if mount_path="$(/usr/libexec/PlistBuddy -c "Print :system-entities:$entity:mount-point" "$work_dir/mount.plist" 2>/dev/null)"; then
        mounted=true
        break
    fi
    entity=$((entity + 1))
done
if [[ "$mounted" != true ]]; then
    printf 'The disk image did not mount.\n' >&2
    exit 1
fi
cp Resources/DMG.DS_Store "$mount_path/.DS_Store"

# Finder writes the icon positions into .DS_Store. A headless build can skip this
# optional refresh while retaining the checked-in drag-to-Applications layout.
if [[ "${AIUSAGE_DMG_NO_FINDER:-0}" != "1" ]]; then
    if ! osascript scripts/layout-dmg.applescript "$mount_path"; then
        printf 'Finder layout refresh unavailable; keeping the saved layout.\n' >&2
    fi
fi

# Set the custom volume icon after Finder has finished updating folder metadata.
cp build/assets/AppIcon.icns "$mount_path/.VolumeIcon.icns"
SetFile -c icnC "$mount_path/.VolumeIcon.icns"
SetFile -a C "$mount_path"
codesign --verify --deep --strict "$mount_path/AIUsage.app"
test -L "$mount_path/Applications"
test -f "$mount_path/.VolumeIcon.icns"
hdiutil detach -quiet "$mount_path"
mounted=false
hdiutil convert -quiet "$work_dir/writable.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$output_path"
hdiutil verify "$output_path"
(cd "$(dirname "$output_path")" && shasum -a 256 "$(basename "$output_path")") > "$output_path.sha256"
printf 'Installer ready: %s\n' "$output_path"
