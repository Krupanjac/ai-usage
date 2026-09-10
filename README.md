# AIUsage

A native macOS menu bar app for Claude Code and Codex usage. It shows plan quota, reset countdowns, and token history from local CLI logs. No LLM requests, price estimates, or analytics.

## Install from a DMG

Download the DMG from the [latest GitHub Release](https://github.com/Krupanjac/ai-usage/releases/latest), quit any running AIUsage copies, and drag **AIUsage** onto **Applications**. Choose **Replace** if an older version is already installed. Eject the disk image, then open AIUsage from Applications. The `arm64` installer is for Apple Silicon Macs running macOS 14 or later.

Look for the blue icon with turquoise, mint, and amber usage bars. The information button in the popover shows the version and the location of the running app. Opening another copy keeps the existing instance running, preventing duplicate menu bar items.

The app in `build/AIUsage.app` is a development build created by the build scripts. Use `/Applications/AIUsage.app` for the installed copy.

## Build and run

Requires macOS 14 or later and a Swift 6 toolchain. Xcode is optional; Apple Command Line Tools are enough. Claude Code and/or Codex should already be signed in.

```sh
make run       # Release build, ad-hoc sign, and open build/AIUsage.app
make debug     # Build a debug app bundle
make install   # Copy to /Applications/AIUsage.app and open it
make dmg       # Create build/AIUsage-<version>-<architecture>.dmg for manual installation
make test      # Swift Testing; no XCTest or external packages
make logs      # Stream AIUsage's indexing/cache diagnostics
make clean
```

Click the chart icon in the menu bar. The two percentages are Claude and Codex, respectively, using the higher of each provider's reported five-hour and weekly usage. A dash means quota is unavailable. The app has no Dock icon.

Use the provider and range selectors to show 24 hourly, 14 daily, or 30 daily bars. Click or drag on the chart to inspect a period. Input, cache reads, cache writes, and output are stacked separately. Totals describe tokens recorded on this Mac; plan quota can include usage from other devices or products, so these measures do not directly correspond.

Install the app in Applications before enabling **Launch at login**. If macOS requests approval, allow AIUsage in System Settings → General → Login Items. The toggle stays off by default.

## Data and credentials

| Provider | Plan quota | Local history |
| --- | --- | --- |
| Claude Code | `api.anthropic.com/api/oauth/usage`, using the existing Claude Code OAuth credential | `~/.claude/projects/**/*.jsonl`, including subagents |
| Codex | `chatgpt.com/backend-api/wham/usage`, with local session quota as a fallback | `~/.codex/sessions/**/*.jsonl` |

Claude credentials are read with Apple's `/usr/bin/security` from the `Claude Code-credentials` Keychain item for the current macOS account, then from `~/.claude/.credentials.json`, then `CLAUDE_CODE_OAUTH_TOKEN`. Codex credentials come from `auth.json` in `CODEX_HOME` (default `~/.codex`). Only ChatGPT login credentials support the quota endpoint. The app uses environment overrides inherited when it starts; Finder-launched apps do not normally inherit terminal shell variables. Codex's authentication options are described in the [official authentication documentation](https://learn.chatgpt.com/docs/auth).

Credentials stay in memory. The app never refreshes them, writes CLI credentials, logs tokens, or sends transcript content over the network. Known expired credentials skip the network request. Sign in again through the relevant CLI when prompted. The quota endpoints are implementation details of the providers and may change; local history remains available if quota fetching fails.

Quota refreshes every five minutes. Manual Refresh has a one-minute floor. Rate limiting uses exponential backoff with jitter, respects `Retry-After` (including HTTP dates), and preserves the retry deadline across restarts. Offline retries back off to fifteen minutes. The newest timestamp wins between network, local-session, and cached quota. Unreported windows stay labeled as unreported rather than showing zero.

## Index and cache

AIUsage stores these files in `~/Library/Application Support/AIUsage/` with owner-only file permissions:

- `index-state.json`: byte offsets, per-file parser state, Claude duplicate keys, UTC hourly token buckets, and the newest local Codex quota.
- `quota-cache.json`: quota snapshots and refresh policy deadlines. No credentials.

History is checked every sixty seconds and when opening the popover if the last check is older than thirty seconds. Reads use 1 MB chunks and never consume an unfinished JSONL line. Unchanged files are not reread. Claude usage is counted once per message/request pair across all files. Codex uses the last response's usage when cumulative totals change, carrying the most recent model forward within each file. Reasoning tokens are already part of output and are not added again.

Daily charts group UTC hourly buckets using the current system calendar and timezone. Because data is stored by UTC hour, day splits in timezones with half-hour or quarter-hour offsets can be approximate. The 24-hour chart includes the current partial hour and the preceding 23 hours.

**Rebuild index** discards the derived index and scans the logs again. Truncation, file replacement, an incompatible schema, or a missing/corrupt cache also triggers rebuilding. Rebuilds checkpoint every fifty files so an interrupted scan can resume. Deleted logs leave additive historical contributions until the next rebuild. Malformed rows are skipped and counted; lines over 16 MB are skipped with bounded memory. CLI log files are never changed.

## Verification and development

`make test` runs parser, chunk-boundary, partial-write, incremental-index, quota, credential-expiry, retry-policy, timezone/DST, and store fallback tests against synthetic fixtures. On Command Line Tools, `scripts/test.sh` adds the framework and runtime search paths that SwiftPM does not discover automatically. On Xcode toolchains it runs `swift test --disable-xctest` directly.

To benchmark real logs and independently verify all indexed token buckets without making quota requests:

```sh
AIUSAGE_BENCHMARK_STATE="$PWD/.context/verification/index-state.json" \
  bash scripts/test.sh -c release --filter liveIndexBenchmark
python3 scripts/verify-local-data.py .context/verification/index-state.json
```

The verifier reads only bytes through each saved offset, so running CLIs may continue appending logs. Its output contains counts and totals, never conversations or credentials. Python 3.9+ is needed only for this optional verifier.

The core library contains credential readers, quota clients, aggregation, the actor-based indexer, and the observable store. The executable contains SwiftUI, Charts, and ServiceManagement views. `scripts/build-app.sh` assembles and signs a standalone app without an auxiliary resource bundle or third-party dependencies. It converts the [icon artwork](Resources/AppIcon.png) into macOS icon sizes with `sips` and `iconutil`.

`make dmg` creates a compressed disk image with the app, an Applications shortcut, install instructions, and a SHA-256 checksum. `Resources/DMG.DS_Store` stores the Finder layout; set `AIUSAGE_DMG_NO_FINDER=1` for headless builds that reuse it without opening Finder. The build uses ad-hoc signing and does not perform Apple notarization. For a downloaded build, macOS may require [Open Anyway in Privacy & Security](https://support.apple.com/en-us/102445).

## Automatic releases

Every push to `main`, including a merged pull request, runs [Release DMG](.github/workflows/release.yml). It runs the regression tests, builds an Apple Silicon DMG, verifies its signature and image checksum, and publishes the DMG and its SHA-256 file on GitHub Releases. Pull requests run the same tests and installer build without publishing. No signing secrets or personal access token are required; publishing uses the workflow's repository token.

Versions are assigned automatically: the workflow run number is added to the patch and build numbers in `Resources/Info.plist`. With the checked-in `1.0.1` / build `2` baseline, the first release run produces `1.0.2` / build `3`, the second produces `1.0.3` / build `4`, and so on. Failed runs can leave gaps. A retry keeps the same version and resumes a draft upload; an already published release is preserved. The source plist is not changed, so there are no version commits that trigger another release.

Keep the patch/build baseline and the release workflow's identity stable within a release series. Change the major or minor version in the plist to start a new series. You can also run **Actions → Release DMG → Run workflow** on `main` to publish manually. The workflow uses [GitHub's macOS Apple Silicon runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and the [GitHub CLI release commands](https://cli.github.com/manual/gh_release_create).

The [latest release link](https://github.com/Krupanjac/ai-usage/releases/latest) stays the same across updates. Installing a new release is manual; AIUsage does not update itself.

See [verification results and remaining manual checks](docs/verification.md) for measurements from the implementation machine.
