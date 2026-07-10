# Continuous producer / liveness / from-cache patterns (image-sampler2)

Proven building blocks for a **local-only continuous producer** plugin (writes a
ring cache, never uploads) plus its companion **from-cache uploader**. All
verified on-node (H00F, Thor). Applies to any producer/consumer split plugin.

## 1. Dual-grid loop (capture grid + heartbeat grid on ONE thread)

A continuous producer often needs TWO independent cadences: capture every N sec,
and a liveness heartbeat every ~M sec (M usually smaller, e.g. capture 60s /
heartbeat 20s). Do NOT mutate the capture loop to also beat — run BOTH grids on
one thread by sleeping to the NEAREST of (next capture edge, next heartbeat edge):

```
start = monotonic()
cap_tick = 0
while True:
    now = monotonic()
    next_cap = start + cap_tick * cap_ns
    next_hb  = heartbeat.next_due_ns(now)
    wake_at  = min(next_cap, next_hb)
    if wake_at > now: sleep((wake_at - now)/1e9)
    now = monotonic()
    if heartbeat.due(now): do_heartbeat(now)     # beat FIRST (startup beat)
    if now >= next_cap:
        do_capture(); cap_tick = (now-start)//cap_ns + 1   # skip-on-overrun
    # ...bounds check at the TAIL (see §4)
```

- **Fire the heartbeat before the capture** on a shared edge so an immediate
  startup beat lands at t=0 (count=0/bytes=0 == "I came up") before any capture.
- **Skip-on-overrun**: recompute `cap_tick` from elapsed so a slow capture jumps
  to the next FUTURE slot in one O(1) step (no catch-up burst).
- Keep both callbacks **fail-soft** (never raise) — the loop must survive a bad
  capture or a broker hiccup.
- **Inject monotonic/sleep** (looked up at call time so monkeypatch works). Tests
  use a fake clock whose `sleep()` advances virtual time — a no-op-sleep + real
  clock will HANG a dual-grid loop (it starves: time never advances past the first
  edge). This bit us migrating Stage-4 tests; the fix is a time-advancing fake.

## 2. Heartbeat = the SOLE liveness signal for a local-only plugin

A `--continuous` local-only producer never uploads, so there is NO upload record
to imply "alive." The heartbeat is the only signal that distinguishes "running
fine, not uploading by design" from "crashed." Design it to:

- Publish cache stats on the beat grid: `env.<plugin>.cache.{count,bytes,written,
  evicted,last_status}` with `meta={cache_name,camera,vsn}` (all meta values must
  be **strings** for pywaggle).
- **Fire even when every capture fails** (dead camera). Reads the ring from disk
  (`scan_ring`) each beat, so it reports true state after failed captures. THIS is
  the case the heartbeat exists to reveal — verified live by pointing at an
  unreachable camera and confirming beats keep landing with count=0/status=skip.
- Use **between-beat deltas** for written/evicted (`snapshot_and_reset`): each beat
  reports only what happened since the last, not cumulative.
- Startup-beat semantic: slot 0 = `[start, start+I)` so `due()` is True at t=0.
- Publish wrapped in try/except (best-effort telemetry, like `plugin.duration.*`).

## 3. from-cache uploader: PRESERVE the original capture-ts end to end

The consumer/uploader half. `--one-shot --from-cache <dir>` uploads the NEWEST
cached file WITHOUT touching the camera, writing, or evicting. The critical
correctness rule (easy to get wrong):

- The cached file ALREADY carries its `<capture_ts_ns>-v2-<vsn>-<camera>.jpg` name
  and embedded EXIF. The upload RECORD timestamp must be that ORIGINAL capture ts:
  `plugin.upload_file(path, meta=meta, timestamp=capture_ts_ns)` — **NOT**
  re-stamped to now. `upload_timestamp` = real send time goes in meta only.
- Recover capture_ts from the filename (`parse_v2_name`); read the rest of the
  meta from embedded EXIF (`read_back_fields`) — do NOT re-embed (that changes
  bytes/unique_id).
- Upload a **COPY** in a temp dir — `upload_file` may move/consume the source, and
  the cached original must survive (no evict/mutate). Verify cache untouched after.
- Reuse the SAME ring scan (`scan_ring`) as the producer for newest-selection, so
  "what is a valid managed v2 file" is defined in exactly ONE place.
- Verified in Beehive: record timestamp == original capture time (back-dated),
  meta.source=from-cache, upload_timestamp later, object under the capture-ts name.

## 4. Clean self-exit bounds (--max-count / --max-runtime)

Let a `--continuous` producer run as a bounded, scheduler-friendly burst instead
of a forever-daemon (pairs with a cron science-rule).

- **Check at the loop TAIL**, after a completed capture, so exit lands on a capture
  edge — never mid-interval. `--max-runtime` also gates on `captures >= 1` so a
  sub-interval runtime still delivers the startup frame.
- `--max-count` counts CAPTURES only (heartbeats/wake-iterations don't count).
- Default both 0 = unbounded (forever behavior preserved exactly). Whichever bound
  trips first wins. Loop returns normally so the `finally:` tears down the Plugin.
- Bounded exit is a SUCCESS (exit 0). On-node: pluginctl streams until the pod
  exits; a bounded pod reaches Succeeded and is reaped (a `timeout` on the
  pluginctl stream would instead KILL the pod — don't confuse the two).
- Keep a test-only loop bound (`max_ticks`) SEPARATE from the production
  `--max-count`: `eff = max_ticks if set else (--max-count or None)`. Tests never
  set --max-count, production never sets max_ticks.

## 5. Dockerfile COPY gotcha

Every new module MUST be added to the Dockerfile `COPY` line, or the on-node build
ImportErrors at runtime (unit tests won't catch it — they import from source).
Caught this twice this project (heartbeat.py). Grep the COPY line against `ls *.py`
before any on-node build.

## 6. On-node creds env-file quoting

Writing a mode-600 creds env-file over SSH: assembling the password inline in a
heredoc/printf can get corrupted by display-masking of secret-looking strings.
Robust pattern: `P=$(printf '%s' 'part1'; printf '%s' 'part2')` then
`printf 'CAMERA_USER=%s\nCAMERA_PASSWORD=%s\n' "$U" "$P" > file`. ALWAYS verify by
length, never by echoing: `awk -F= '/PASSWORD/{print "pw_len=" length($2)}' file`.
