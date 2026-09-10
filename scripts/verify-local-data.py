#!/usr/bin/env python3
"""Independently compare an AIUsage index with exactly the log bytes it indexed.

Reads logs without displaying conversations, credentials, or request IDs.
"""
import argparse
import collections
import datetime as dt
import json
import os
import pathlib
import sys
from zoneinfo import ZoneInfo


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("state", type=pathlib.Path)
    parser.add_argument("--claude-root", type=pathlib.Path, default=pathlib.Path.home() / ".claude/projects")
    parser.add_argument("--codex-root", type=pathlib.Path,
                        default=pathlib.Path(os.environ.get("CODEX_HOME", str(pathlib.Path.home() / ".codex"))).expanduser() / "sessions")
    parser.add_argument("--timezone", default="Europe/Belgrade")
    args = parser.parse_args()
    state = json.loads(args.state.read_text())
    expected = collections.defaultdict(lambda: [0, 0, 0, 0])
    seen = set()
    event_counts = collections.Counter()
    newest_quota = None
    for filename, indexed in sorted(state["files"].items()):
        path = pathlib.Path(filename)
        if args.claude_root in path.parents:
            provider = "claude"
        elif args.codex_root in path.parents:
            provider = "codex"
        else:
            raise ValueError("An indexed file is outside the configured log roots")
        model, previous = "Unknown", None
        with path.open("rb") as source:
            while source.tell() < indexed["offset"]:
                raw = source.readline()
                if not raw or source.tell() > indexed["offset"]:
                    break
                if not any(marker in raw for marker in (b'"assistant"', b'"token_count"', b'"turn_context"')):
                    continue
                try:
                    row = json.loads(raw)
                except (ValueError, UnicodeError):
                    continue
                if provider == "claude":
                    message = row.get("message") or {}
                    usage = message.get("usage") or {}
                    if (row.get("type") != "assistant" or not row.get("requestId") or not message.get("id")
                            or not message.get("model") or message.get("model") == "<synthetic>"):
                        continue
                    model = message["model"]
                    amounts = [usage.get(key, 0) or 0 for key in
                               ("input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")]
                    key = message["id"] + ":" + row["requestId"]
                    if key in seen or not sum(amounts):
                        continue
                    seen.add(key)
                else:
                    payload = row.get("payload") or {}
                    if row.get("type") == "turn_context":
                        model = payload.get("model") or model
                        continue
                    if row.get("type") != "event_msg" or payload.get("type") != "token_count":
                        continue
                    limits = payload.get("rate_limits") or {}
                    windows = [limits.get(key) for key in ("primary", "secondary")]
                    valid = [w for w in windows if w and w.get("window_minutes") in (300, 10080) and w.get("used_percent") is not None]
                    if limits.get("limit_id") in (None, "codex") and valid:
                        stamp = dt.datetime.fromisoformat(row["timestamp"].replace("Z", "+00:00")).timestamp()
                        if newest_quota is None or stamp > newest_quota[0]:
                            newest_quota = (stamp, {w["window_minutes"]: w["used_percent"] for w in valid})
                    info = payload.get("info") or {}
                    total = (info.get("total_token_usage") or {}).get("total_tokens")
                    if total is None:
                        continue
                    old, previous = previous, total
                    usage = info.get("last_token_usage")
                    if old == total or not usage:
                        continue
                    cached = max(0, usage.get("cached_input_tokens", 0) or 0)
                    amounts = [max(0, (usage.get("input_tokens", 0) or 0) - cached), usage.get("output_tokens", 0) or 0,
                               cached, usage.get("cache_write_input_tokens", 0) or 0]
                amounts = [max(0, amount) for amount in amounts]
                if not sum(amounts):
                    continue
                date = dt.datetime.fromisoformat(row["timestamp"].replace("Z", "+00:00"))
                hour = int(date.timestamp() // 3600) * 3600
                key = f"{hour}|{provider}|{model}"
                expected[key] = [a + b for a, b in zip(expected[key], amounts)]
                event_counts[provider] += 1
    actual = {key: [bucket["totals"][field] for field in ("input", "output", "cacheRead", "cacheWrite")]
              for key, bucket in state["buckets"].items()}
    mismatches = sum(expected.get(key) != actual.get(key) for key in expected.keys() | actual.keys())
    totals = collections.defaultdict(lambda: [0, 0, 0, 0])
    today_totals = collections.Counter()
    timezone = ZoneInfo(args.timezone)
    today = dt.datetime.now(timezone).date()
    for key, amounts in expected.items():
        hour, provider, _ = key.split("|", 2)
        totals[provider] = [a + b for a, b in zip(totals[provider], amounts)]
        if dt.datetime.fromtimestamp(int(hour), timezone).date() == today:
            today_totals[provider] += sum(amounts)
    quota_matches = True
    if newest_quota:
        quota = state.get("newestCodexRateLimits") or {}
        actual_windows = {minutes: quota[key]["usedPercent"] for minutes, key in ((300, "fiveHour"), (10080, "weekly")) if quota.get(key)}
        quota_matches = actual_windows == newest_quota[1] and abs(quota.get("asOf", 0) + 978307200 - newest_quota[0]) < 0.001
    print(json.dumps({"files": len(state["files"]), "buckets": len(expected), "mismatched_buckets": mismatches,
                      "local_quota_matches": quota_matches, "events": dict(event_counts),
                      "totals_input_output_cacheRead_cacheWrite": dict(totals),
                      "today_tokens": dict(today_totals), "timezone": args.timezone}, indent=2))
    return 1 if mismatches or not quota_matches else 0


if __name__ == "__main__":
    sys.exit(main())
