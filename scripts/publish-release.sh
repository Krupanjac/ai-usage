#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

commit="$(git rev-parse "${1:-HEAD}^{commit}")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/AIUsage.app/Contents/Info.plist)"
tag="v$version"
asset="AIUsage-$version-$(uname -m).dmg"
notes_file="${2:-Resources/ReleaseNotes.md}"
test -f "build/$asset"
(cd build && shasum -a 256 --check "$asset.sha256")

# A rerun can resume an interrupted upload, but cannot replace a published build.
if existing="$(gh release view "$tag" --json targetCommitish,isDraft,url --jq '[.targetCommitish, .isDraft, .url] | @tsv' 2>/dev/null)"; then
    IFS=$'\t' read -r target is_draft release_url <<< "$existing"
    if [[ "$target" != "$commit" ]]; then
        printf 'Release %s belongs to a different commit; refusing to replace it.\n' "$tag" >&2
        exit 1
    fi
    if [[ "$is_draft" != true ]]; then
        printf 'Already published: %s\n' "$release_url"
        exit 0
    fi
    gh release upload "$tag" "build/$asset" "build/$asset.sha256" --clobber
    gh release edit "$tag" --draft=false
else
    gh release create "$tag" "build/$asset" "build/$asset.sha256" \
        --target "$commit" --title "AIUsage $version" --notes-file "$notes_file" --generate-notes
fi
gh release view "$tag" --json url --jq .url
