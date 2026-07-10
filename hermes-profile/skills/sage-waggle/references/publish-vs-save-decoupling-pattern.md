# Publish-always / save-selectively: decoupling reporting from media upload

A reusable design pattern for Sage camera/audio plugins (bioclip, birdnet,
yolo). It separates **what the plugin reports** (cheap measurement topics) from
**what media it saves** (expensive image/audio/clip uploads to Beehive). They
have very different costs and should be controlled by two different flags.

## The core idea

- `--min-confidence` = the **reporting floor**. The minimum confidence for a
  detection to be PUBLISHED as a topic. Raise it to reduce noisy reports. It
  must NOT control media saving.
- `--save-match` = the **save selector**. The ONLY thing that uploads media.
  An OR-list of `Name:confidence` rules; media is saved when ANY published
  detection matches ANY rule.

This replaces the old anti-pattern where the same `--min-confidence` gate both
published AND uploaded — which forced a single threshold to serve two
unrelated purposes (you couldn't report broadly but save selectively).

## The two code paths (keep them visibly separate in the run loop)

```
# PATH 1: PUBLISH (always)
published = [d for d in detections if d.confidence >= args.min_confidence]
if published:
    plugin.publish(<per-detection topics>, ...)
# Heartbeat: ALWAYS publish, even with zero confident detections, so the data
# plane proves the cycle ran (distinguishes "running, nothing seen" from "dead").
plugin.publish("<...>.summary", json.dumps({"published_count": len(published),
               "top_confidence": top_conf_or_0}), ...)

# PATH 2: SAVE (selective)
if save_rules and should_save(save_rules, published, name_keys=[...]):
    plugin.upload_file(<annotated image / audio clip>, meta={...})
```

Omitting `--save-match` => save NOTHING (opt-in). This is a deliberate
behavior change when upgrading a job: a plugin bumped to the save-match version
WITHOUT a `--save-match` arg will keep publishing topics but STOP uploading
media until a rule is added. Call this out in the CHANGELOG `### Migration`
section, and add `--save-match "*:<old-threshold>"` to existing jobs to
reproduce the previous "upload anything above threshold" behavior.

## The shared matcher helper (save_match.py)

`parse_save_match(spec) -> list[Rule]` and
`should_save(rules, detections, name_keys) -> bool`. Key design choices proven
this session:

- **Name-field-agnostic**: caller passes `name_keys` (the meta keys that hold
  candidate names). bioclip uses `["name","common_name"]`, birdnet uses
  `["common_name","scientific_name"]`, yolo uses the COCO class name. One helper,
  three callers.
- **Matching is EXACT + case-insensitive on common OR scientific name. NO
  substring matching.** `"Northern Cardinal"` matches, bare `"Cardinal"` matches
  nothing. Document this loudly — users will otherwise expect substring.
- **Wildcard `*`**: `"*:0.7"` saves any detection >= 0.7.
- **OR semantics**: comma-separated rules; save if ANY (rule x detection) hits.
  One media file saved ONCE per cycle even if several detections match.
- **FAIL FAST at startup**: parse `--save-match` immediately after
  `parse_args()` and `sys.exit(2)` / `raise SystemExit(2)` on a malformed rule
  or out-of-range confidence. A typo'd save rule that silently saves nothing
  would waste an entire deployment.
- Copied IDENTICALLY into each plugin repo for now (no shared package); plan a
  refactor to one package later to avoid drift. Add `COPY save_match.py .` to
  the Dockerfile (before `COPY app.py .`) and a `save-match` input to sage.yaml
  (type "string").
- Run the 29-test pure-Python suite (`python3 tests/test_save_match.py`) in
  every repo after copying — it needs no pytest and no deps.

## CRITICAL PITFALL: the heartbeat must not be gated behind `if detections:`

Real bug found AND confirmed live this session in birdnet 0.1.6. The
`publish_detections()` function internally always emitted the summary
heartbeat, BUT the CALL SITE wrapped it:

```
if detections:                       # <-- BUG
    publish_detections(plugin, detections, ts)
```

So on quiet (zero-detection) cycles, `publish_detections` was never called and
NO heartbeat was published — a live job looked dead in the data plane. Fix: call
it unconditionally (gate only on `plugin is not None` for dry-run):

```
if plugin is not None:
    publish_detections(plugin, detections, ts)   # emits heartbeat even when empty
```

How it was confirmed in production: the job kept emitting `plugin.duration.*`
every cycle (proving the pod fired on schedule) but ZERO
`env.detection.audio.summary` during a pre-dawn quiet window. Telemetry present +
heartbeat absent == this exact bug. Always verify the heartbeat fires on a
ZERO-detection cycle, not just on a cycle with detections.

## Verifying the two paths in the data plane

- **Negative path** (quiet cycle): heartbeat record present with
  `published_count: 0`, and ZERO `upload` records. Easy to confirm any time.
- **Positive path** (confident detection): an `upload` record appears with meta
  carrying `top_species` / `confidence`. For a camera plugin this needs a real
  subject in frame, so it is daylight/activity-dependent — see the timing trap
  below. Do not declare the feature "done" until you have observed BOTH paths.

## Timing trap: cron-window misses and pre-dawn quiet

Two scheduler-timing facts bit verification this session:

1. **Cron fires on the exact minute.** A job with science rule
   `cronjob(..., '20 * * * *')` launches at :20 only. If you `submit` at :22
   (two minutes after the tick), the FIRST launch is next hour's :20 — not
   immediately. Don't read "no data yet" right after submit as a failure; check
   the cron minute vs. submit time.
2. **Pre-dawn = no positives.** Camera/audio bird plugins produce no confident
   detections in the dark. Convert UTC to the node's local time before
   concluding anything: H00F is US Central (UTC-5/6). At ~04:00 local, max
   confidence ~0.1-0.3 and zero detections is EXPECTED, not a bug. Schedule the
   positive-path watcher for first light (~06:00 local) instead of spinning.

Watcher pattern that works: background SSH loop polling the data API every
~3 min for the first matching record (an `upload` for save-path, or a non-zero
`summary` for detections), with `notify_on_complete=true`. Time the watcher to
SPAN the expected window — an earlier watcher that expired at :31 missed a :40
cron launch entirely.
