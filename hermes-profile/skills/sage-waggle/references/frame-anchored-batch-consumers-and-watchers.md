# Frame-anchored batch output breaks time-windowed pollers (watchers/triggers)

Hard-won this session (2026-07): a Slack watcher silently missed EVERY bird
detection from sage-yolo2 v2 for days. Neither component was individually buggy —
it was a contract mismatch between a batch/frame-anchored PUBLISHER and a
short-window POLLER. Any external "cloud trigger" (watcher that polls the Sage
data API and acts on detections) that consumes a batch plugin's output will hit
this.

## The trap

Two properties combine to make records invisible to a naive poller:

1. **Frame-anchored timestamps.** A pywaggle2 cache-consumer (sage-yolo2 v2)
   publishes each record with `timestamp = the frame's CAPTURE time`, NOT the
   time it published. This is correct and deliberate (a detection is about when
   the scene existed). See `pywaggle2-producer-consumer-architecture`.
2. **Batch cadence.** The consumer wakes every ~10 min (`--every 10m`) and
   publishes the whole backlog at once — dozens of records in one burst, each
   stamped MINUTES in the past, non-monotonic, out of order.

So a bird captured at 12:21 is only published (~12:30 wake) and queryable (~12:31
after cross-country object-store lag), by which point its own timestamp is
already ~10 min old. A poller that filters on a short recent window (the classic
`start=-120s` lookback) NEVER sees it. Permanently invisible. The detection IS in
the data API — `env.count.bird=1` at 12:21:17, conf 0.887 — the watcher just
never queried a window that contained it.

## Diagnosis pattern

- Confirm the detection actually published: query the data API for the exact
  measurement at the frame's capture timestamp (the ns prefix of the v2
  filename `<ts_ns>-v2-<vsn>-<cam>.jpg` IS the record timestamp). If it's there,
  the publisher is fine and the bug is downstream.
- Check the consumer's cadence: is it batch (`--every 10m`) or continuous? Batch
  + frame-anchored ⇒ suspect the poller's lookback window immediately.
- Note the burst signature: many `env.count.*` records sharing one publish
  instant but spread across minutes of capture timestamps = batch + frame-anchor.

## Design principle: the poller must be PUBLISHER-AGNOSTIC (user-corrected 2026-07)

Pete's explicit steer when reviewing the fix: the watcher must make NO assumption
about how often the upstream samples or publishes — "it simply polls on a recent
time window, and then finds the new reports, and processes them." Do NOT frame
the design (in code comments, help text, or README) around a specific plugin's
cadence (e.g. "sage-yolo2's ~10-min batch"). Frame it generically: poll a recent
window → find records not seen before (per-record dedup) → process them. The
frame-anchored-batch case is then just ONE example of why per-record dedup +
wide window is the robust design, not the premise. `--lookback` is documented as
"wider than the publisher's worst-case detection-to-queryable delay (its
batch/aggregation latency, if any, plus object-store lag)" — covering real-time
AND batch publishers with one design. This keeps the watcher reusable for any
Sage measurement, not coupled to today's plugin.

## The fix (correct way to poll a frame-anchored batch publisher)

DO NOT compensate by shortening the consumer's batch period or by publishing
publish-time timestamps — frame-anchoring is a feature. Fix the POLLER:

1. **Wide lookback** ≥ (batch period + object-store propagation lag + margin).
   For a 10-min batch: 15 min (900s). This guarantees a freshly published
   back-dated record still falls inside the query window.
2. **Seen-ID dedup, NOT a last-timestamp high-water mark.** Because records are
   back-dated and arrive out of order/en masse, "newest timestamp seen" is not a
   valid watermark — an older-stamped record can arrive AFTER a newer one. Track
   a bounded SET of stable per-record keys (`f"{timestamp}|{name}"`); any unseen
   positive record is new and fires exactly once, even while it lingers in the
   wide window for many polls.
3. **Startup seeding.** On start, pre-mark everything currently in the lookback
   window as seen (a plain restart must not re-alert on old detections). Provide
   a `--replay` flag to skip seeding and surface a recently-missed detection once.
4. **Cooldown is anti-spam only.** With per-record dedup, a blanket multi-minute
   cooldown adds nothing but RISK — it swallows distinct, genuinely-new events
   (rare birds). Keep it tiny (~30s) or drop it.

Minimal shape (extract to functions so it's testable, not inline in the loop):
```python
def detection_key(r): return f"{r.get('timestamp','')}|{r.get('name','')}"

def filter_new_detections(records, seen, order, *, mark):
    new = [r for r in records
           if _positive(r) and detection_key(r) not in seen]
    if mark: _mark_seen(new, seen, order)
    return new                       # loop uses mark=False, then _mark_seen on notify

def _mark_seen(records, seen, order):
    for r in records:
        k = detection_key(r)
        if k not in seen: seen.add(k); order.append(k)
    while len(order) > MAX_SEEN: seen.discard(order.pop(0))   # bounded FIFO
```
Loop filters with `mark=False` (so a detection found DURING cooldown stays "new"
until actually notified — else it's dropped), then `_mark_seen` only after a
successful post.

## Secondary watcher gotchas seen the same session

- **Plugin-name drift v1→v2.** The watcher's annotated-image lookup filtered on
  the v1 name `yolo-object-counter`; the v2 plugin is `sage-yolo2`, so even a
  fired alert found no image. Watch for hard-coded v1 plugin names after a
  rename.
- **Dead measurements after a class-filter change.** Watcher still polled
  `env.count.person`/`env.count.fork` after the consumer was set bird-only
  (`--classes bird`). Harmless but stale — keep the watch list in sync with the
  consumer's `--classes`.
- **`env.count.<class>` carries empty meta; `env.count.total` has the rich meta**
  (camera, model, classes summary). A watcher reading only the per-class topic
  shows `camera/model: unknown`. Read `env.count.total` if you need that context.
- **Object-store propagation lag is LONGER than you think — size the retry
  deadline generously.** A freshly-published `upload` record's blob 404s until it
  propagates through the cross-country object store. The commonly-cited "~2 min"
  is optimistic: measured this session, of 3 annotated bird images, one served in
  61 s but TWO were still 404 at 240 s — yet all three returned HTTP 200 when
  re-checked later. A 240 s (4-min) retry deadline therefore LOST ~2/3 of images
  to slow propagation, not to failed uploads. Fix: (a) fetch via a deferred,
  retrying queue (post the text alert immediately; the photo follows), never
  inline; (b) set the give-up deadline to ~600 s (10 min), not 4 min. Diagnostic
  to distinguish "slow" from "never uploaded": re-curl the storage URL with the
  Sage token later — a 200 proves it was only slow, so extend the deadline rather
  than chase a phantom upload bug.
- **Transient data-API 5xx / read timeouts happen.** The Sage data API threw
  HTTP 500s and read-operation timeouts for several minutes this session; a
  robust watcher logs and keeps polling (fail-soft in the loop's try/except)
  rather than crashing. Backend flakiness also worsens image-propagation delays,
  another reason for the generous retry deadline above.

## Operability

- **BEFORE launching a watcher, check whether a DURABLE one already exists**
  (learned the hard way 2026-07 — spawned duplicate watchers repeatedly). A prior
  session may have installed a systemd USER unit; a bare `ps | grep` for the
  script isn't enough. Check `systemctl --user list-units | grep <name>` and
  inspect each running PID's PARENT (`ps -o ppid= -p <pid>` → is it `systemd` or
  your shell/agent?). systemd-parented = the durable one, KEEP it; agent/shell-
  parented = your stray duplicate, KILL it. Two watchers polling one node = double
  alerts. After a code change, `systemctl --user restart <unit>` to pick it up —
  don't hand-launch a second copy alongside the service.
- **`pgrep -f "<script>"` / `pkill -f` SELF-MATCH the grep's own command line**
  (the pattern string appears in the pgrep argv). Filter it out
  (`grep -v pgrep`, `grep python3`) or a phantom PID / an exit-code -15 self-kill
  appears. Also, a hardline blocklist rejects any command containing the literal
  word "reboot" (even inside a grep pattern) — phrase durability checks as
  "survive a restart" / "on boot", never grep for that word.
- Reboot survival = a systemd USER unit that is BOTH `enabled` AND has user
  LINGER on (`loginctl show-user <u> -p Linger` → yes). Without linger a user
  service dies at logout and never starts on boot — enabled alone is not enough.
  A good unit: `Restart=always`, `RestartSec`, `After=network-online.target`,
  `StartLimitBurst` storm cap, `StandardOutput=journal`.
- Don't launch a long-lived watcher with stdout to a detached socket (output is
  then unrecoverable — `/proc/<pid>/fd/1 -> socket:[...]`). Redirect to a log
  file and gitignore it, OR use a systemd unit and read it via
  `journalctl --user -u <unit>` (the journal, not a file, is where a service's
  history lives — don't look for a log file that the service never wrote).
- Verify batch/dedup logic with an ad-hoc harness that imports the REAL
  extracted functions (not a reimplementation): assert first-sighting fires,
  re-poll does NOT re-fire while still in window, zero-counts ignored, distinct
  detection fires, bounded eviction caps the set, malformed values don't crash.
