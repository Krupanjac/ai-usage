#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_path="${1:-$PWD/build/AIUsage.app}"
if pgrep -x AIUsage >/dev/null; then
    pkill -x AIUsage || true
    for attempt in {1..50}; do
        if ! pgrep -x AIUsage >/dev/null; then break; fi
        sleep 0.1
    done
fi
open -n "$app_path"
