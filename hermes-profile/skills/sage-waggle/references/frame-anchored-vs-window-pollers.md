# Frame-anchored batch publishing breaks short-window pollers (the watcher trap)

Task class: a downstream WATCHER/alerter/consumer polls the Sage data API for a
plugin's detections and "silently misses" hits the plugin definitely published.
VERIFIED root cause on H00F 2026-07 (slack-hummingbird bird watcher missed a
confirmed `env.count.bird=1` that YOLO published at 88.7% conf).

## The mismatch (why it happens)

pywaggle2 batch consumers (e.g. sage-yolo2 `--every 10m`) publish every record
**FRAME-ANCHORED**: the record's `timestamp` is the frame's CAPTURE time, NOT the
publish time. So a bird captured at 12:21 is only processed + published at the
next ~10-min batch wake (~12:30), then needs ~1-2 min of cross-country object-
store propagation before it's queryable (~12:31-12:32). By the moment it FIRST
becomes visible, its own `timestamp` is already ~10 min in the PAST.

A poller that filters on a short lookback window (the classic
`start = "-120s"`) therefore NEVER sees it: the record's timestamp falls outside
every 2-min window the poller ever queries. The detection is permanently
invisible even though it's in the data plane. This is a DESIGN mismatch, not a
bug in either component — the watcher was written for the OLD continuous plugin
where publish-time ≈ capture-time ≈ now.

## Diagnosis pattern (confirm it's this, not a detection-code miss)

1. Confirm the detection EXISTS: query the exact measurement + timestamp
   (frame filename `<ts_ns>-v2-<vsn>-<cam>.jpg` → the ts prefix IS the record
   timestamp). If `env.count.bird=1` is there, the plugin did its job.
2. Confirm the SPREAD: query `env.count.total` for the batch window; you'll see
   ~N records published in one burst, each carrying a back-dated (capture) ts
   spanning minutes. That burst-of-back-dated-records IS the signature.
3. Confirm the poller's window can't reach it: if `now - record_ts >> lookback`,
   the poller structurally cannot see it. Case closed.

## The fix: wide lookback + per-record seen-ID dedup (NOT a time high-water mark)

Two coupled changes — a wide window alone would re-alert forever; dedup alone
wouldn't widen reach:
- **Lookback ≥ batch period + propagation + margin.** For a 10-min batch: 15 min
  (900s). Set it comfortably above `--every` + ~2 min object-store lag.
- **Dedup on a STABLE per-record key**, e.g. `f"{timestamp}|{name}"`, held in a
  bounded set (FIFO-evict at a cap like 5000). Do NOT use a single
  `last_notified_ts` high-water mark: frame-anchored batch records arrive en
  masse with back-dated, NON-MONOTONIC timestamps, so "newest ts seen" is not a
  valid watermark — an older-ts record in the same burst would be wrongly skipped
  or wrongly re-fired.
- **Startup seeding + a `--replay` flag.** On a routine restart, pre-mark every
  positive detection already in the lookback window as SEEN (so you don't spam
  old hits); `--replay` skips seeding to intentionally surface a recently-missed
  one. Seed via the SAME dedup function with mark=True.
- **Filter with mark=False in the loop; mark seen only AFTER a successful
  notify.** A detection found during a cooldown must stay "new" until it's
  actually sent, or it's silently dropped.
- **Cooldown:** a blanket multi-minute cooldown SWALLOWS distinct rare events
  (the seen-ID set already prevents duplicate alerts of the SAME record), so keep
  it small (anti-spam only). For rare subjects (birds <1/hr) 30s is plenty.

Extract the dedup into a real function both the loop and the startup seed call
(`filter_new_detections(records, seen, order, *, mark)` + `_mark_seen`) so it's
directly unit-testable rather than reimplemented in a test — the inline-in-main
version can't be verified without reproducing it.

## Secondary staleness to check when a watcher was written for a v1 plugin

When the upstream plugin was renamed/re-versioned (e.g. `yolo-object-counter` v1
→ `sage-yolo2` v2), a watcher hard-codes assumptions that silently rot:
- Plugin-name substring used to match `upload` records (`meta.plugin`) — update
  to the new name or the annotated-image fetch finds nothing.
- Watched measurement list — if the plugin was reconfigured (e.g. bird-only),
  drop the now-dead measurements (`env.count.person`/`.fork`) it no longer emits.

## Operability gotcha: capture the watcher's own logs to a FILE

A long-lived watcher started from a since-detached shell has its stdout going to
a dead socket (`/proc/<pid>/fd/1 -> socket:[...]`), so its history is
unreadable when you need to debug a miss. Launch with `python3 -u ... >>
watcher.log 2>&1` so the run log survives. (Also: `pkill -f "<pattern>"` over a
matching shell SELF-MATCHES and returns exit -15/255 while killing its own
shell; prefer kill-by-PID or a systemd unit.)

## Ad-hoc verification when the repo has no test suite

A standalone watcher/util often has no `make test`. Write a throwaway
`/tmp/hermes-verify-*.py` that imports the module by path
(`importlib.util.spec_from_file_location` — works even for hyphenated filenames)
and calls the REAL extracted functions against stubbed records: dedup fires once
/ doesn't re-fire while in-window / distinct fires / zero-count ignored / seed
marks without alerting / bounded eviction / malformed value skipped / formatter
degrades on empty meta. Run, then delete. Report explicitly as ad-hoc, not suite
green.
