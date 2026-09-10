# AIUsage

A native macOS menu bar app for Claude Code and Codex usage. It shows plan quota, reset countdowns, and token history from local CLI logs. No LLM requests, price estimates, or analytics.

## Build and run

Requires macOS 14 or later and a Swift 6 toolchain. Xcode is optional; Apple Command Line Tools are enough. Claude Code and/or Codex should already be signed in.

```sh
make run       # Release build, ad-hoc sign, and open build/AIUsage.app
make debug     # Build a debug app bundle
make install   # Copy to /Applications/AIUsage.app and open it
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

The core library contains credential readers, quota clients, aggregation, the actor-based indexer, and the observable store. The executable contains SwiftUI, Charts, and ServiceManagement views. `scripts/build-app.sh` assembles and signs a standalone app without an auxiliary resource bundle or third-party dependencies.

See [verification results and remaining manual checks](docs/verification.md) for measurements from the implementation machine.
