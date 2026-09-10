#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# GitHub preserves the run number on retries and increments it for every new run.
# Adding it to the checked-in baseline avoids publishing the same version twice.
run_number="${1:?Pass the GitHub Actions run number}"
[[ "$run_number" =~ ^[1-9][0-9]*$ ]] || { printf 'Invalid release run number.\n' >&2; exit 1; }
baseline="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
[[ "$baseline" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || { printf 'Invalid baseline version.\n' >&2; exit 1; }
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
printf 'AIUSAGE_VERSION=%s.%s.%s\n' "$major" "$minor" "$((10#$patch + run_number))"
printf 'AIUSAGE_BUILD_NUMBER=%s\n' "$((build_number + run_number))"
