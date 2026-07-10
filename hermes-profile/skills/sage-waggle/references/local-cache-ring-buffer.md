# Local-cache ring buffer for continuous Sage camera plugins

Durable design for a `--continuous` camera plugin that writes frames to a LOCAL
directory (not the cloud) as a bounded ring buffer, so a SEPARATE trigger plugin
can later pick up relevant frames (e.g. audio detects a lightning strike at T-10s
→ trigger reads the cache for frames near that instant and uploads them; or a
remote node's wildfire alert prompts a local agent to pull matching-time frames).
Distilled from the image-sampler2 design work, 2026-07. Pairs with the fixed-
period loop in `scheduling-continuous-vs-oneshot-and-gpu-contention.md` §3b and
the naming/metadata rules in `image-metadata-naming-and-eventlog-linking.md`.

## Mode split (two DIFFERENT sinks)

- `--one-shot`  → upload + publish to the cloud (classic imagesampler behavior;
  the upload/event-log/EXIF linking design applies here).
- `--continuous <SECONDS>` → write to a LOCAL cache (see `--cache-root` below),
  bounded ring buffer, no unconditional upload. (Whether continuous EVER uploads a
  selected frame — a triggered subset — is a separate policy decision; the
  sampler's only obligation is to make the cache discoverable + readable.)
  SECONDS is INTEGER only (no fractional — keeps the fixed-period scheduler simple).

Prefer two descriptive, mutually-exclusive argparse flags over one ambiguous flag
like `--cronjob`. The cache flag is **`--cache-root`** (rename any legacy
`--cache-dir`/`--out-dir`); it is REJECTED with `--one-shot` (fail-fast).

### `--cache-root` defaults to `/local-cache` (SUPERSEDED interim: /tmp fallback)

> SUPERSEDED [2026-07-08]: the auto-detect-with-`/tmp`-fallback described in this
> subsection was the INTERIM build-now scheme. Pete later had the `/tmp` fallback
> REMOVED entirely — `/local-cache` is now the unconditional default and the plugin
> fail-fasts if it's absent. See "Producer fail-fast: /local-cache is REQUIRED, no
> fallback [FINAL]" below for the current behavior. Kept here for design-record +
> the reusable "default-to-future-path, fall-back-to-stopgap" pattern, which is
> still valid for a capability that is TRULY not-yet-shipped (unlike /local-cache,
> which now exists via wes-local-cache-manager).

When the CI team hasn't yet provisioned a shared cache mount but you want to build
+ verify the PRODUCER now: make the cache location a ROOT + subtree, with the root
AUTO-DETECTED so the eventual cutover is zero-touch.
- Flag `--cache-root` = BASE dir. Default resolves, first that applies:
  `$IS2_CACHE_ROOT` env → `/local-cache` (if it `isdir`) → `/tmp`. Explicit flag
  always wins. mkdir -p + writability check → fail-fast if unwritable.
- Subtree: `<cache-root>/<cache-name>/<camera>/<ts>-v2-...jpg`. `--cache-name`
  overrides the middle segment; default = the JOB id (from `WAGGLE_APP_ID`/env,
  safe fallback if unset), mirroring the future `/local-cache/<job>/...` convention
  so consumers have a predictable place to look. Validate `--cache-name` is
  filesystem-safe (letters/digits/dot/dash/underscore, no path separators).
- **Interim `/tmp` scope boundary:** `/tmp` inside a pod is pod-local, wiped on pod
  restart, and NOT visible to other consumer pods. So the PRODUCER is fully
  functional and testable, but the cross-pod CONSUMER story does NOT work until a
  real persistent, cross-consumer `/local-cache` mount exists. Verify the producer
  in isolation now; keep the startup-adoption/crash-safety code (it's correct — it
  just only demonstrably matters within one pod lifetime until `/local-cache` gives
  restart persistence). Write ALL cache code assuming a real persistent
  `/local-cache`; `/tmp` is only a stopgap.
This is a reusable pattern for any plugin feature that depends on a not-yet-shipped
CI capability: default to the future path if present, fall back to a working
stopgap, so the real capability is picked up with no flag/code change.

### Producer fail-fast: /local-cache is REQUIRED, no fallback [FINAL, 2026-07-08]

DESIGN EVOLUTION — read this whole block; the earlier three-tier scheme was
SUPERSEDED same-session by Pete. The learning is the ARC, because it's a recurring
pattern: a fallback that is a fine DEV convenience becomes a PRODUCTION footgun,
and the clean end-state is to DELETE the fallback, not to gate it behind an opt-in.

- **Interim state (early this session):** the silent `/tmp` fallback plus a
  three-tier opt-in: a `--require-local-cache` flag + env twin
  `IS2_REQUIRE_LOCAL_CACHE=1` to force fail-fast; explicitly-named `/local-cache`
  also fail-fast; bare auto-detect fell back to `/tmp` with a LOUD warning.
- **Pete's call (final):** "remove the /tmp hack — it was good for dev but is cruft
  that confuses students; the newest plugin assumes the right /local-cache and no
  longer supports the /tmp that does not really work." Rationale worth
  remembering: a fallback that silently "works" but produces data no consumer can
  read is worse for a teaching/production audience than a clean error. When a
  requirement becomes universal, the opt-in flag to request it is REDUNDANT —
  delete it rather than keep it as ceremony.

**FINAL semantics (image-sampler2 `cache.py`/`app.py`, unit-tested + live-verified):**
- `resolve_cache_root()` is a PURE one-liner: `--cache-root` > `$IS2_CACHE_ROOT` >
  `/local-cache`. NO filesystem probe, NO `/tmp` branch, no `TMP_CACHE_DIR`
  constant. (Making resolve pure — presence enforced separately — is cleaner than
  the old isdir-probing resolve.)
- `assert_cache_root_available(cache_root)` (single arg, no `required` kwarg):
  the resolved root MUST already exist as a writable dir, else raise the existing
  config-time `CacheError` → `EXIT_CONFIG_ERROR` (2). The message names the
  `wes-local-cache-manager` component and the `-v <host>:/local-cache` mount fix,
  and reports the offending dir by name (so an explicit `--cache-root /foo` that's
  absent is reported as `/foo`). No silent fallback anywhere.
- `--cache-root <dir>` REMAINS as the explicit off-node dev escape hatch (point it
  at any existing writable dir) — that's the ONE sanctioned way to run without
  `/local-cache`, and it still fail-fasts if the named dir is missing.
- REMOVED: the `--require-local-cache` flag, the `IS2_REQUIRE_LOCAL_CACHE` env
  twin, `require_local_cache_requested()`, `assert_shared_cache_available(...,
  required=)`, `TMP_CACHE_DIR`, and the app.py interim-/tmp warning branch. Net
  −93 LOC — the removal genuinely simplified the code (KISS win, not just a
  behavior change).
- Keep the check a PURE helper that raises `CacheError` so app.py's existing
  config-error handler reports it, and it unit-tests with monkeypatched
  `os.path.isdir`/`os.access` (no real FS). When you delete an API like this, also
  sweep DOCS for stale mentions (jobs/README, top-level README, design notes): fix
  user-facing docs to the new behavior, and mark a historical design note as
  SUPERSEDED rather than rewriting its record.

GENERAL RULE distilled: don't reach for a `--require-X` opt-in when X is meant to
be always-on — make X the unconditional default and fail-fast without it; keep a
single explicit override (`--cache-root`) for the genuine dev exception. An env
twin for a flag is only worth adding when the flag actually survives; here the flag
itself was cut.

### Adoption doc for a new WES component: DESIGN-AND-PURPOSE.md [2026-07-08]
When handing a new WES service to the upstream team, write a standalone
`DESIGN-AND-PURPOSE.md` in its repo that a sysadmin/dev can adopt with NO prior
context — deliberately WITHOUT the history of prior attempts/shortcomings. Proven
structure: (1) the gap it fills, framed as a side-by-side table vs the existing
sibling service (`/uploads` cloud-bound-transient vs `/local-cache`
share-on-node-retained; same hostPath+DaemonSet shape); (2) what it does (the two
caps); (3) the Layer-1/Layer-2 model with ONE worked example (image-sampler2) PLUS
a non-image example (a rolling DB/table) to prove it's not domain-specific; (4)
why a filesystem sweep not a k8s quota; (5) the temporary start/teardown scripts
described step-by-step, each step tagged as an ansible-migration candidate, since
it's not yet in Ansible; (6) config reference table; (7) what a plugin dev must do;
(8) future enhancements stated as explicitly out-of-scope (notably: NO discovery
mechanism yet). Link it from the README. Keep the deep design rationale in a
separate design doc; DESIGN-AND-PURPOSE is the adoption front-door.

## Ring-buffer bounding

Two independent caps, evict-on-EITHER: `--cache-max-count N` and `--cache-max-mb M`
(decimal MB, 10^6). At least ONE must be set with `--continuous` (else unbounded
growth) → fail-fast if neither. "Size" = total bytes of the MANAGED set (files
matching the plugin's own name pattern); `.tmp` and unknown files are not counted.

## The corner cases that bite (all resolved)

- **Per-stream rings, not one shared dir.** Each `--stream` is its own process; a
  shared cache dir → cross-process eviction RACE. Give each stream its own
  subdir `<cache-dir>/<camera>/`, each an INDEPENDENT ring with per-stream caps.
  No locks, race-free. **ENFORCE it (a1, Pete decision 2026-07-06): ONE plugin
  instance = ONE camera stream.** `--continuous` with `>1 --stream` is a FAIL-FAST
  config error ("supports exactly one --stream; run a separate plugin/job per
  camera"). Top+bottom cameras = two separate jobs. This removes all intra-process
  concurrency: one scheduler, one ring, one fail-soft path — greatly simpler code +
  accounting. (Leave `--stream` a repeatable list so the CLI shape is unchanged and
  `--one-shot`, which just uses `stream[0]`, is undisturbed — the single-stream rule
  is scoped to continuous mode only.)
  **AT LEAST ONE `--stream` is MANDATORY (fail-fast) — a common live-launch trap.**
  Running with a camera host + creds but NO `--stream` dies immediately with
  `config error: at least one --stream is required` (exit 2), and via pluginctl
  shows only as `Plugin failed to run ... remains in the system` — inspect the pod
  logs to see it's this config error, NOT an RBAC/image problem. `--stream` is the
  camera identifier/label even for a native-still (Reolink `Snap`) fetch where the
  URL comes from `CAMERA_HOST`/creds: the code uses `camera_name = name[0] if
  --name else stream[0]` purely to LABEL the ring dir, so any stream id (e.g.
  `top_camera`) works — it need not be a URL. Always include `--stream <id>` in
  every continuous invocation.
- **"Oldest" by the capture-ts prefix in the filename**, not mtime (mtime lies if
  the clock stepped). Fallback to mtime only for non-matching files; leave unknown
  files untouched + uncounted.
- **Stateless management.** Scan the subdir each capture; compute; decide. No
  authoritative in-memory ring state → crash/restart just re-scans. Add an
  in-memory index only if profiling demands, rebuilt from disk at startup.
- **Startup adoption.** Adopt existing name-matching files into the ring (count,
  size, evict). Never wipe the dir at startup; ignore non-matching files.
- **Evict BEFORE the file joins the ring (ordering guarantee).** Per capture:
  1. acquire into a `.tmp` so `new_bytes` is known (`.tmp` is NOT a ring member);
  2. scan → current_count/current_bytes, oldest-first;
  3. E3 guard: if a size cap is set and `new_bytes > max_bytes` even with an empty
     ring, DROP the new image with a loud warning + delete `.tmp` (keep the cache
     valid rather than let one file exceed the cap);
  4. evict-LOOP oldest while `count+1 > max_count` OR `bytes+new_bytes > max_bytes`
     (a single delete is insufficient for a large new frame under a size cap);
  5. atomic write: fsync `.tmp` then `os.replace(.tmp → final name)`. The final
     name appears atomically and only NOW joins the ring — so the ring never
     transiently exceeds caps and no torn `.jpg` ever exists under the final name.
- **Fail-SOFT at runtime, fail-FAST at config.** Eviction-delete failure
  (locked/permission) or disk-full → WARN + skip/continue; never crash a
  long-running process. Missing/unwritable cache-dir, no cap set, or flags misused
  across modes → fail-fast at startup.
- **Ring sizing ≥ trigger lookback.** A trigger wanting frames from T-10s can lose
  them if the ring already evicted under load. Size the cache to exceed the LONGEST
  trigger lookback window (N seconds of frames at the sampling rate). Document it.

## Liveness heartbeat — the sole aliveness signal for a local-only producer [Stage 5, 2026-07]

A `--continuous` local-only producer NEVER uploads, so there is no upload record
in the data plane to imply "alive." Without a heartbeat the fleet cannot tell
"running fine, not uploading by design" from "crashed / camera dead." So a
continuous producer MUST publish a periodic cache heartbeat. Rules that verified
well on-node (image-sampler2 Stage 5, H00F):

- **Dual-grid, one thread.** Run the capture loop and the heartbeat on TWO
  independent monotonic grids in one single-threaded loop. Each iteration sleeps
  to the NEAREST of (next capture edge, next heartbeat edge), then fires whichever
  grid(s) are due. This keeps the heartbeat on its own ~60s cadence even when the
  sample interval is much LONGER (a 5-min timelapse still reports alive every
  ~60s), while never emitting >1 beat per slot when sampling is FASTER. A single-
  grid loop that only wakes per capture would bottleneck the heartbeat to the
  capture interval — do NOT do that.
- **`--heartbeat-secs` is INDEPENDENT of `--continuous SECONDS`** (default ~60,
  continuous-only, positive-int fail-fast, rejected in one-shot like the cache
  flags). Add it to the same one-shot-rejection set as `--cache-*`.
- **Startup beat.** Slot 0 = `[start, start+I)`, so the first heartbeat fires
  IMMEDIATELY at loop start (count=0/bytes=0) — an "I came up" signal before the
  first capture. A long stall emits exactly ONE catch-up beat, never a burst.
- **Fires even when every capture FAILS** — that "running but silent" case is the
  whole reason it exists. Read the ring from disk (re-scan) so the payload is true
  state after a run of failures. Verified live by pointing at a dead camera IP:
  every capture logged `Connection refused` yet heartbeats kept landing in the
  data plane with count=0/status=skip.
- **Payload + topics** (keep the `env.imagesampler.cache.*` namespace):
  `env.imagesampler.cache.{count,bytes,written,evicted,last_status}` where
  written/evicted are DELTAS since the last beat (reset each beat) and last_status
  ∈ ok|skip|fail|none. `meta={cache_name,camera,vsn}` all strings, so multi-stream
  nodes disaggregate. pywaggle `plugin.publish(name,value,timestamp=ns,meta={})`
  accepts arbitrary dotted names + ns timestamps + string meta (no forced prefix).
- **Open a pywaggle Plugin fail-SOFT.** Continuous didn't need a Plugin before
  (never uploads); the heartbeat does. If the Plugin can't be created (bare
  off-node test), log a warning and run WITHOUT heartbeats — the cache still
  works. Wrap each `publish` in try/except: a broken RabbitMQ broker must NEVER
  kill the capture loop.
- Keep the pure heartbeat logic (grid + accumulators: `due()`/`next_due_ns()`/
  `record_capture()`/`snapshot_and_reset()`) in its own module, no I/O, so it's
  unit-testable with a fake clock.

## Testing grid-gated loops: the fake clock MUST advance on sleep() [TRAP, 2026-07]

A common Stage-4 test pattern was `monkeypatch app.time.sleep -> no-op` + the REAL
`time.monotonic_ns`. That works for a loop that captures EVERY iteration
(`run_capture_loop`), but it HANGS a grid-GATED loop (the dual-grid loop): with a
no-op sleep and a near-frozen real clock, the loop wakes but `now < next_edge`, so
it never fires and never bounds → infinite spin. FIX: inject a FAKE CLOCK whose
`sleep(secs)` ADVANCES virtual `monotonic_ns` by `secs`. Make the loop's
`monotonic`/`sleep` injectable (defaulted via `time.*` looked up at CALL time so
monkeypatch still works) and thread the same injection through the continuous
handler so tests drive it deterministically without real waits. Also: bound such
a loop by NUMBER OF CAPTURES (`max_captures`), not wake-iterations — with two grids
"N iterations" ≠ "N captures", which silently breaks count-based assertions.
Also remember tests that build args via `parse_args(...)` directly BYPASS
`validate_args` (where defaults like `heartbeat_secs=60` get applied) — either call
`validate_args` in the test or set the field on the namespace, else the handler
sees `None`.

## `--from-cache` uploader — the consumer/uploader half (composition, not a flag) [Stage 6, 2026-07]

The periodic-snapshot need ("upload one cloud frame every ~30 min") is met by
COMPOSITION, not by adding an upload flag to the local-only producer. Keep the
producer a pure producer; add a SEPARATE uploader mode that reads the cache:
- `--one-shot --from-cache <dir>` = take the NEWEST v2 image already in `<dir>` and
  upload it via the EXISTING one-shot upload path — no camera contact, no write, no
  evict. Schedule it on an SES cron (`*/30 * * * *`). This is also the reference
  "read cache → act" pattern other consumers (YOLO/BioClip/BirdNet) follow.
- `--from-cache` is one-shot-only (fail-fast with `--continuous`); `<dir>` is the
  STREAM dir (the leaf `<cache-root>/<cache-name>/<camera>/` that directly holds
  the jpgs), unambiguous with one-camera-per-stream.

Rules that verified on-node (image-sampler2 Stage 6, H00F):
- **PRESERVE the original capture-ts end to end.** The cached file ALREADY has its
  `<capture_ts_ns>-v2-...jpg` name + embedded EXIF. The upload RECORD timestamp
  must be that ORIGINAL capture ts (`plugin.upload_file(timestamp=capture_ts)`),
  NOT re-stamped to now. `upload_timestamp` (meta) = the real send time. Recover
  capture-ts authoritatively from the v2 NAME (`parse_v2_name`); take vsn/camera +
  unique_id/acquisition_path from the embedded EXIF (`read_back_fields`), falling
  back to the name-parsed vsn/camera. Verified in Beehive: record ts = capture
  time, upload_timestamp = send time, `source=from-cache`, unique_id from EXIF.
- **Do NOT re-capture or re-embed** — that would change bytes/unique_id. Read the
  file as-is.
- **Upload a COPY** (pywaggle `upload_file` may move/consume the source). The
  cached original must stay untouched (no evict/mutate) — verified: file count +
  bytes identical after upload.
- **Reuse `scan_ring` for selection** (newest = max capture_ts_ns) so "what is a
  valid managed v2 file" is defined in ONE place (ignores `.tmp`/non-v2).
- **Exit codes:** empty/missing cache dir → fail-fast EXIT_CONFIG_ERROR (a
  scheduled uploader firing against an empty cache is a real misconfig worth
  surfacing — chosen over silent exit 0). Runtime read/upload failure → the
  capture-error code. `plugin.duration.upload` only (no grab/embed phases).
- **Ship a turnkey job PAIR** (`jobs/producer-continuous.yaml` +
  `jobs/uploader-from-cache.yaml` + README): the two must agree on
  `--cache-root`/`--cache-name`/`--stream`. Producer reads camera creds from
  env/Secret (never argv); the uploader needs NO creds (never hits the camera).

## `--max-count` / `--max-runtime` clean self-exit for windowed scheduling [Stage 3.3, 2026-07]

Give a `--continuous` producer optional bounds so it can run as a bounded,
scheduler-friendly BURST (cron fires it; it captures for a window then exits and
frees the slot) instead of a forever-daemon — fleet parity with the yolo
`--continuous Y --max-runtime 600` cron pattern.
- `--max-count N` = exit after N CAPTURES (heartbeats/wake-iterations do NOT count
  — a heartbeat is telemetry, not work product). `--max-runtime S` = exit after S
  wall-clock seconds. Both default 0 = UNBOUNDED (forever behavior preserved
  exactly). Continuous-only (rejected in one-shot), non-negative ints (negative →
  fail-fast). Bounded self-exit is a SUCCESS (exit 0), not an error.
- **Check at the loop TAIL, after the capture block, before the next sleep**, so
  exit lands on a COMPLETED-CAPTURE edge — never mid-interval. Gate the runtime
  check on `captures >= 1` so a sub-interval `--max-runtime` still delivers the
  startup frame. Whichever bound trips first ends the loop; it RETURNS normally so
  the caller's `finally` (Plugin teardown) runs cleanly.
- In the dual-grid loop, `max_runtime_ns` is the wall-clock bound; the production
  `--max-count` maps onto the SAME capture counter the test harness uses
  (`max_captures`). Keep the test injection (`max_ticks`) and the production
  `--max-count` SEPARATE — effective bound = whichever is set (tests never set
  `--max-count`, production never sets `max_ticks`).
- For a pure-CPU plugin (no GPU to free) this is about scheduler COMPOSABILITY +
  fleet parity, not resource contention — genuinely useful but lower urgency than
  it is for GPU-sharing plugins. Fully unit-testable with the fake clock; a real-
  clock smoke test (`--max-count 3` → exactly 3 frames → exit 0 in ~2s) confirms
  the production path returns on its own, not just via a test bound.

## Cross-plugin visibility (what makes the trigger-consumer pattern work)

For a DIFFERENT plugin/pod to read the cache, it must live on a filesystem region
shared across pods on the node. Each WES plugin runs as its own pod with its own
container FS by default — pod A's files are invisible to pod B UNLESS the cache
sits on a HOST-PATH volume mounted into both pods.

VERIFIED on-node (H00F + edge-scheduler 0.28.0 `resourcemanager.go`, 2026-07):
a host-backed, restart-persistent, cross-pod shared mount DEFINITELY EXISTS.
- WES injects into EVERY plugin pod a hostPath volume:
  host `/media/plugin-data/uploads/<JOB>/<NAME>/<TAG>` → pod `/run/waggle/uploads`
  (read-write). `/media/plugin-data` is on the node root NVMe (937G on H00F) →
  PERSISTS across pod restart AND node reboot (not pod-ephemeral). Already
  structured per-plugin-instance on disk (`bioclip-species-classifier-5647/`...).
- Because it's a hostPath, a file one pod writes is readable by ANY other pod
  mounting the same hostPath — that IS the cross-plugin sharing mechanism.
- Also mounted: `/run/waggle/data-config.json`. Injected env incl. `WAGGLE_APP_ID`
  (pod uid), `HOST` (node name). Pod: ShareProcessNamespace=true, SA
  `wes-plugin-account`, RestartPolicy Never, finished pods GC'd ~60s.
- `wes-data-sharing-service` is RabbitMQ MESSAGING, NOT a filesystem share — don't
  confuse it with FS sharing.
- User volumes (`uservolume-N`) allow an arbitrary hostPath BUT the scheduler
  source warns they REQUIRE a nodeSelector or the pod fails to schedule.

### The upload-agent contract — NEVER put a local-only ring under the uploads mount [RESOLVED 2026-07-06, from source]

Resolved empirically by reading the upload-agent source
(`waggle-sensor/wes-upload-agent`, `main.sh` — it's a bash rsync loop, not Go).
Definitive behavior:
- The agent loops forever over `/uploads` (host `/media/plugin-data/uploads`),
  running `find . -mindepth 3 -maxdepth 4 -type d` filtered to paths shaped like
  `[<job>/]<plugin>/<version>/<ts>-<sha1hex>/` where `<version>` matches
  `x.y.z | vx.y.z | latest | test` and the leaf matches `<digits>-<hexdigits>`
  (the pywaggle staging dir holding `{data,meta}`). Test fixtures `missing-data`/
  `missing-meta` show it validates each item has both files.
- For every match it `rsync ... --remove-source-files` to beehive, i.e. it
  **UPLOADS AND THEN DELETES the source**, and `rmdir`s emptied dirs.
- README confirms: "Items of the form `/uploads/x/y` will be moved to beehive."

CONSEQUENCE for a LOCAL-ONLY ring: option (A) "write under the uploads mount" is
**doubly wrong** — the agent would (i) upload files you must never upload, and
(ii) DELETE your ring files out from under your own eviction logic. Even if your
flat filename (`<ts>-v2-<vsn>-<camera>.jpg`, no data/meta pair, no `x.y.z/` dir)
does not match the regex TODAY, relying on out-guessing the agent's scan is
fragile. So:

**Cache home decision: always (B) — a dedicated subtree OUTSIDE the uploads mount.
Never point a local-only cache at `/run/waggle/uploads`.**

How to check any watcher's scope this way generally: read the agent's source (or
its README) rather than probing production. `wes-upload-agent` is `main.sh` +
`common.sh` in the repo root; `find_uploads_in_cwd()` is the scan function.
Reading the SES `edge-scheduler` `resourcemanager.go` is how the pod mount/env
injection was confirmed. Prefer source-reading over `kubectl exec` into a live
system pod (exec-ing the upload-agent also dumps its private SSH push key — do not
record/reuse it).

### Storage quota + two-layer eviction — no per-plugin cap exists today [source-verified 2026-07-08]

Source-read of `edge-scheduler` (`pkg/nodescheduler/resourcemanager.go`,
`pkg/datatype/plugin.go`) + WES `kubernetes/*.yaml`. Establishes what bounds
plugin disk use TODAY and how a shared `/local-cache` must be bounded.

- **NO per-plugin storage quota exists.** `resourceListForConfig` maps a plugin's
  `sage.yaml` `resource:` map to k8s, but ONLY these keys: `limit.cpu`,
  `limit.memory`, `limit.gpu`, `request.cpu`, `request.memory`. There is NO
  `ephemeral-storage` case. Unrecognized keys fall through a `default:` branch as
  a raw limit — so `resource: {"limit.ephemeral-storage":"2Gi"}` WOULD be honored,
  but it's undocumented/accidental and nothing uses it. The cluster LimitRange
  (`wes-default-limits.yaml`) sets only default memory (1Gi limit / 300Mi req /
  500m cpu) — no storage default, and there is NO ResourceQuota anywhere.
- **The only disk backstop today is kubelet node `nodefs` disk-pressure eviction**
  (generic k3s default ~10%/5%). Evidence they rely on it: `wes-upload-agent` has a
  `node.kubernetes.io/disk-pressure` toleration so it keeps draining under
  pressure. This protects the NODE, not a well-behaved neighbor, and may evict the
  wrong pod. So Pete's instinct is source-confirmed: no graceful per-plugin cap.
- **hostPath writes escape ALL k8s storage accounting.** A shared, node-persistent,
  cross-pod `/local-cache` MUST be a hostPath (emptyDir/`/tmp` is pod-private).
  hostPath bytes are NOT counted against `ephemeral-storage` limits or emptyDir
  `sizeLimit`, and node `nodefs` eviction may miss them if the cache is on a
  separate mount. => the ONLY things that can bound `/local-cache` are a
  filesystem project quota (XFS/ext4) or a dedicated sweeper. Design the cap in;
  do not assume k8s provides it.
- **pluginSpec ALREADY has a `Volume` hostPath field** (`plugin.go`
  `Volume map[string]string`; `resourcemanager.go:776` mounts each as
  `uservolume-N` hostPath DirectoryOrCreate). So the tracker claim "job schema
  exposes no volume mount" (Infra #9) is PARTLY WRONG — the field EXISTS. Real
  gaps are narrower: it requires a nodeSelector (else FailedScheduling), has an
  unresolved root-ownership security TODO in the source, and is undocumented.

**Two-layer eviction design (the correct split).** Graceful policy and blunt
quota are different responsibilities and live in different places:
- **LAYER 1 — policy (graceful, semantic): the PLUGIN / pywaggle2.** Only the
  plugin knows its data's meaning (images-by-count/MB for image-sampler2, LRU rows
  for a SQLite consumer, keep-last-N-per-camera, …). WES must NOT own this — a
  plugin-global eviction strategy is impossible because each plugin's data differs.
  Owns "what to keep." (This is image-sampler2's ring in cache.py; hoist to a
  pywaggle2 cache primitive `Plugin.cache_file()`/`read_cache()` mirroring
  `upload_file()`.)
- **LAYER 2 — quota (blunt, safety): a WES manager pod.** A per-plugin-subdir hard
  byte cap + per-node total, oldest-first purge, fires ONLY when a plugin
  misbehaves. Semantics-free by design — acceptable to delete "important" data
  precisely because it's a last-resort backstop. Owns "don't let anyone eat the
  disk." Prefer per-plugin-subdir isolation (one greedy plugin can't starve
  another's cache) over a single shared pool with only a global cap.

**`wes-local-cache-manager` DaemonSet — model it on `wes-upload-agent`.** WES
services ARE each their own pod (44 in `kubernetes/`: upload-agent is a DaemonSet,
gps-server a Deployment, …). So yes — the cache manager should be its own pod. The
upload-agent is the exact template (it already does the analogous job for
`/uploads`):
- Mounts the shared cache ROOT `hostPath: /media/plugin-data/local-cache` →
  `/local-cache` (parent of all `<ns>/<plugin>/` subdirs), exactly as upload-agent
  mounts the uploads parent `/media/plugin-data/uploads`.
- Runs the LAYER-2 sweeper: walk each subdir, enforce per-subdir + per-node caps,
  delete oldest-first only when exceeded. Does NOT do graceful eviction (that's
  Layer 1 in the plugin).
- `priorityClassName: system-node-critical` + `node.kubernetes.io/disk-pressure`
  toleration so it keeps reclaiming under pressure, like upload-agent.
- **Where it lives:** it's WES infra → `waggle-edge-stack` repo as
  `kubernetes/wes-local-cache-manager.yaml` + a small `waggle/wes-local-cache-manager`
  image, deployed per-node like upload-agent. Host dir `/media/plugin-data/local-cache`
  provisioned in the same ansible/node-setup that already creates
  `/media/plugin-data/uploads`. Manager-pod sweeper is more portable than
  XFS/ext4 project quotas (filesystem-agnostic) → lean manager-pod-as-primary,
  mention project quotas as optional hardening.

Clean division to hand the WES team: **WES provides the mounted, persistent,
read/write/graceful-evict semantics on top (Layer 1).** Neither alone suffices.

**A working Layer-2 prototype EXISTS + verified** (`wes-local-cache-manager`,
2026-07-08): DaemonSet modeled on upload-agent, stdlib two-pass sweeper
(per-unit then node-wide, oldest-first, catches strays), `RUN_ONCE`/`DRY_RUN`
test hooks, health-file liveness, + a node test-add/teardown script whose steps
are tagged as ansible candidates. Build/deploy/verify HOW-TO:
`wes-node-service-daemonset-sideload.md`.

### Cross-user read permissions — still OPEN, and unsolvable until a shared mount exists
Exact write uid + whether a DIFFERENT-user consumer pod can read the files
("visible to all users" → likely world/group-readable files + traversable dirs;
`chmod` on write if needed) CANNOT be resolved under an interim `/tmp` root (no
cross-pod visibility to permission in the first place). Defer this to when the real
persistent `/local-cache` mount lands (see the interim-pattern section under Mode
split above); it does NOT block producer work.

Design implications once a shared root exists:
- **Uniqueness key for the instance path** must be PREDICTABLE by the consumer.
  Prefer a stable user-supplied `--cache-name`/instance label over the SES job id
  (changes every resubmit) or an opaque content hash. Path shape:
  `<SHARED_ROOT>/image-sampler2/<cache-name>/<camera>/...`.
- **Discovery**: convention-glob is fragile with multiple users/configs on one
  node; consider having the sampler PUBLISH a small manifest/record announcing
  "caching camera X, config Y, at path P" so consumers find it at runtime.
- **Cross-node choreography is out of scope for the sampler** — it only makes the
  local cache discoverable + readable; the remote-alert → local-reader signaling
  lives in a separate agent.
- POSIX safety: a consumer reading a file while the ring `unlink`s it is safe (the
  reader keeps its fd); atomic writes (above) prevent torn reads.
