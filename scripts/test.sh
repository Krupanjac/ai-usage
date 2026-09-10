#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
developer_path="$(xcode-select -p)"
framework_path="$developer_path/Library/Developer/Frameworks"
if [[ -d "$framework_path/Testing.framework" ]]; then
    # CLT ships Testing, but SwiftPM does not discover its framework or interop dylib.
    exec swift test --disable-xctest \
        -Xswiftc -F -Xswiftc "$framework_path" \
        -Xlinker -F -Xlinker "$framework_path" \
        -Xlinker -rpath -Xlinker "$framework_path" \
        -Xlinker -rpath -Xlinker "$developer_path/Library/Developer/usr/lib" "$@"
else
    exec swift test --disable-xctest "$@"
fi
