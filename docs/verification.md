# Implementation verification

Verified on 2026-09-10 with Apple Swift 6.3.3 and the macOS 26.5 SDK from Command Line Tools. The installed app is `/Applications/AIUsage.app`.

| Check | Result |
| --- | --- |
| Release app assembly and ad-hoc signature | Pass; `codesign --verify --deep --strict` |
| Tests | 25 regression tests pass through `make test`; real-log benchmark is a separate opt-in test |
| Native menu bar behavior | Icon and percentages appear, clicking the icon opens/closes the popover, process has `background only = true` |
| Claude credential access | Existing Keychain item readable through `security`; no repeated prompt observed across rebuilds |
| Network quota | Both endpoints returned successfully; cached snapshots contain the decoded usage windows |
| Codex local quota | Independently matches the newest qualifying session snapshot; absent five-hour window remains unreported |
| Token history | Independent Python scan matches all 432 buckets across 555 log files, with zero mismatches |
| Cold indexing | Approximately 1.97 seconds for 1.32 GB in the final release core |
| Cached indexing | Approximately 44 ms, reading zero log bytes in the measured warm run |
| Parsing errors | Two malformed rows skipped; no unreadable files in the final real-log verification |
| Offline / expired / unauthorized / 429 | Covered with injected providers/transports, including cache fallback and persisted retry deadlines |
| Partial writes / truncation / cache removal | Covered with real temporary files and incremental/rebuild assertions |
| Reusable buffer boundaries | Empty rows, UTF-8 splits, exact size limits, oversized rows, and seven chunk sizes covered |
| Chart UI | Visually inspected at native width; provider and range controls exercised through Accessibility |
| Launch at login | Registration and unregistration succeeded from Applications; restored to off after testing |
| Relaunch | Installed app restarts successfully with the launch script's process-exit wait |

Memory was measured separately from indexing time. The final core-only scan used about 34 MB of physical memory. The app settled around 43 MB of physical memory with its popover closed; shortly after a rebuild with the popover open it used about 61 MB, with a measured transient peak around 178 MB. Physical footprint and RSS are different measurements: the plan's strict **RSS below 60 MB target is not met** by the complete SwiftUI/Charts app (RSS was approximately 120 MB after exercising the UI).

Physical mouse injection was blocked by macOS assistive-access permissions, so chart pointer selection and a literal outside-click dismissal still need manual confirmation. The native `chartXSelection` interaction is implemented; menu-icon toggling and the rendered layout were checked. Network loss and 429 behavior were simulated without disconnecting the machine or deliberately exhausting a provider's endpoint.

## Reproduce

```sh
make test
make install
AIUSAGE_BENCHMARK_STATE="$PWD/.context/verification/index-state.json" \
  bash scripts/test.sh -c release --filter liveIndexBenchmark
python3 scripts/verify-local-data.py .context/verification/index-state.json
footprint -p AIUsage --noCategories
```

The benchmark and independent verifier do not make quota requests. Scratch measurements and screenshots are in the gitignored `.context/verification/` directory. No credentials or transcript contents are part of the repository.

## Version 1.0.1 installer and releases

Verified on 2026-09-10. This installer was built for manual installation; the existing `/Applications/AIUsage.app` was left in place.

| Check | Result |
| --- | --- |
| Regression tests | 25 pass; opt-in live benchmark skipped |
| App icon | All standard/Retina macOS sizes packaged with `iconutil`; 128px rendering and Finder installer visually checked |
| DMG integrity | `hdiutil verify` passes; app signature verified again inside the mounted final image |
| Installer contents | Version 1.0.1 / build 2, app icon, volume icon, Applications shortcut, install instructions, and saved Finder layout verified |
| Duplicate copies | Opening `build/AIUsage.app` while the installed app ran exited the new instance; the original installed process remained the only running copy |
| Workflow definitions | `actionlint` passes for pull-request CI and automatic main releases |
| Release numbering | Run 1 produces 1.0.2 / build 3; run 2 produces 1.0.3 / build 4; invalid counters rejected |
| Headless release build | Built and mounted 1.0.2 / build 3 with overrides; saved layout, volume icon, and signature verified |
| Publishing retries | Mocked CLI checks cover new release creation, resuming a draft upload, preserving a published release, and rejecting a conflicting commit |

Release numbering is applied to the assembled bundle through environment overrides. The workflow does not edit or push the source plist. The initial 1.0.1 release is built locally; automatic publishing begins when the workflow changes reach `main`. These builds use ad-hoc signing and are not notarized by Apple.
