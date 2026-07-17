# Plugin scheduling on a node: continuous vs one-shot, and single-GPU contention

Hard-won lessons from operating yolo + bioclip + birdnet on Thor node H00F
(single GPU, hummingbird cam). These govern HOW to schedule camera/audio
plugins, not just how to deploy them.

> RELATED TRAP: a BATCH consumer (`--every 10m`) publishes FRAME-ANCHORED
> records (timestamp = CAPTURE time, not publish time), which silently breaks any
> downstream watcher/alerter polling with a short lookback window — a confirmed
> detection is published but never falls inside the poller's window. Diagnosis +
> fix (wide lookback + per-record seen-ID dedup, NOT a time high-water mark):
> see `references/frame-anchored-vs-window-pollers.md`.

## 1. Sampling rate is a first-class design decision — it broke detection once

Moving the YOLO hummingbird-cam plugin from a **continuous pod**
(`--continuous Y --interval 60`, ~1440 frames/day) to a **`*/10` one-shot
cron** (~144 frames/day) silently collapsed bird detections from ~15/day to
~0. The watcher (which triggers on `env.count.bird`) went silent for ~2 days.

Root cause: NOT a detection-code regression — the 10× sampling drop. A
hummingbird is in-frame only a few seconds, so sampling once per 10 min
almost never coincides with a visit.

**Rule of thumb:**
- Fast / intermittent subjects (hummingbirds, traffic, people) → **continuous**,
  `--continuous Y --interval 60` (or tighter). Pod stays running; model stays warm.
- Slow-changing scenes (clouds, snow depth, parking occupancy) → **one-shot**
  cron is cheaper and fine.

**Self-sleep (continuous pod) vs SES one-shot cron — how to actually decide.**
First rule out GPU contention as a factor (it usually isn't — see §3): on a
big-unified-memory node like Thor a sleeping continuous consumer costs ~zero
compute and negligible memory, so it does NOT block co-tenants and "needs a
dedicated GPU" is FALSE there. Once contention is off the table the choice is
about RELIABILITY, and cron usually wins:
- Cold-start cost: self-sleep loads the model ONCE (warm); cron reloads every
  tick (~2–5 s YOLO, ~1 min BioCLIP). Self-sleep's only real advantage.
- Reboot survival: cron/SES respawns after a node reboot; a `pluginctl run` or
  bare continuous pod does NOT come back on its own.
- Crash blast radius: a crash in a self-sleep loop kills ALL future wakes; a
  cron tick dies alone and the next tick is a clean pod (self-healing).
- Scheduler visibility: cron/SES jobs get restart policy + accounting; a
  `pluginctl run` pod is invisible to SES.
- Prereq: SES cron needs the plugin's ECR catalog record; `pluginctl run` does
  not. The seen-store makes one-shot batches equivalent to self-sleep batches
  (each fresh pod reads persisted dedup memory, processes only new frames).
Lean: long-period / short-batch / shared big-memory node → SES one-shot cron.
Dedicated GPU or cold-start-sensitive → self-sleep.

**Diagnosis pattern** (proved root cause without guessing): query the data API
for `env.count.total` records PER DAY over the suspected window. A collapse in
*ticks/day* (not in the bird-specific topic) points to a sampling/scheduling
change, not a model bug:
```python
from collections import Counter
# recs = data API query for env.count.total, last 5d, sorted by timestamp
by_day = Counter(r["timestamp"][:10] for r in recs)   # ticks/day
# 1205, 1419, 1425, 250, 62  ->  the cliff is the schedule change date
```

## 2. Big-model plugins pay a COLD START as one-shot

BioCLIP 2.5 ViT-H/14 is a ~28 GB image/model. As a one-shot it RELOADS the
whole model every cron tick. Continuous loads once and keeps it warm. Another
reason to prefer continuous for large vision models on the bird cam.

## 3. GPU sharing: THREE distinct kinds of "contention" — do not conflate them

CRITICAL DISTINCTION (an earlier version of this ref wrongly claimed "two
always-on GPU plugins CANNOT share one GPU" as if it were a hardware/GPU-memory
law — it is NOT). There are THREE independent mechanisms; know which one you're
actually hitting before choosing a fix:

**(a) GPU COMPUTE (SM time) — time-sliced, NEVER exclusive by default.** The CUDA
driver interleaves kernels from all processes. A plugin contends for compute
ONLY while it is actively issuing kernels (during inference — a few seconds per
batch). A plugin that is **sleeping** (`time.sleep(600)` between wakes, or idle
between captures) issues ZERO kernels and is not on the GPU computationally at
all — a co-tenant gets 100% of the compute. So a **resident-but-sleeping model
does NOT lock out another plugin's compute.** True hard compute exclusion only
happens if a process explicitly claims it: `nvidia-smi -c EXCLUSIVE_PROCESS`
compute mode, or CUDA MPS configured to serialize. We do NOT set those, so
compute is shared.

**(b) GPU MEMORY (VRAM/unified) — the only real STEADY-STATE cost, node-dependent.**
A loaded model + CUDA context stay resident for the pod's whole life, including
sleep windows (YOLO11x ≈ 5 GB; BioCLIP ViT-H/14 ≈ 28 GB). Whether that blocks a
co-tenant is PURELY a function of the node's memory budget:
- **Thor / H00F — Jetson UNIFIED memory ≈ 122 GB (~69 GB free, verified 2026-07).**
  5 GB + 28 GB resident is a rounding error → **two heavy models coexist fine;
  memory contention is a NON-ISSUE.** A sleeping YOLO here does NOT lock out
  BioCLIP — neither on compute (it's asleep) nor on memory (ample headroom).
- **NX / Xavier / small discrete GPU ≈ 8–16 GB VRAM.** Two resident heavy models
  EXHAUST VRAM → the second OOMs or fails to load. THIS is where "can't share"
  is real, and the fix is to free VRAM between runs (one-shot cron, or windowing
  — see Resolution A).
So: **"does a sleeping plugin block another" is answered by VRAM headroom, not by
the mere fact that it's resident.** Check `free -h` / `tegrastats` RAM before
assuming contention.

**(c) The WES SCHEDULER placement policy — a SOFTWARE gate, not a hardware limit.**
Observed on H00F: yolo continuous (job 5650) placed first, then bioclip continuous
(job 5651) — SES `stat -j 5651` said "Running" but **no pod was ever created**.
This was NOT the GPU refusing them — it was the WES node scheduler declining to
place a second plugin holding `selector: resource.gpu: "true"`. Thor/WES does NOT
model the GPU as a k8s `nvidia.com/gpu` resource; `resource.gpu: "true"` is a
Waggle SCHEDULER selector, so `kubectl describe node` shows no GPU allocation and
the block is invisible in plain k8s views. IMPORTANT NUANCE: `pluginctl run` pods
go to the `default` namespace and do NOT carry this SES selector, so two
`pluginctl run` GPU pods (e.g. a producer + a consumer, or two consumers) DO
co-schedule on Thor and run concurrently — the placement gate is specific to the
SES `resource.gpu` selector path, not a universal "one GPU plugin per node" rule.

Key tell for (c): SES `stat -j <id>` "Running" (cloud schedule accepted) ≠ a pod
actually running. ALWAYS confirm with `kubectl get pods -n ses` + the data API.

### Decision shortcut — which mechanism am I hitting, and does it exclude other code?
- Plugins EXCLUDE each other's COMPUTE only under explicit EXCLUSIVE_PROCESS/MPS
  (we don't use them) → normally compute is shared, sleeping plugins cost 0.
- Plugins contend on MEMORY only when resident models exceed the node's RAM/VRAM
  → real on small-VRAM nodes, negligible on Thor's 122 GB unified memory.
- Plugins get BLOCKED FROM PLACEMENT by the WES scheduler's `resource.gpu`
  selector when submitted as SES jobs → a scheduler policy, dodge-able via
  windowing/one-shot, or (for testing) via `pluginctl run` which skips the gate.
Only (a)-with-EXCLUSIVE and (b)-on-a-small-node are genuine HARDWARE exclusion.
(c) is a schedule policy. On Thor, none of them force serialization for typical
5–28 GB models — so co-running is fine and the continuous-vs-cron choice there is
about RELIABILITY (reboot survival, self-healing), not GPU contention.

**Resolution A — WINDOWED time-slicing (preferred when you want BOTH models
running on their own cadence on one GPU).** Add a `--max-runtime N` flag to each
plugin: in `--continuous Y` mode the plugin loops every `--interval` seconds then
SELF-EXITS after N seconds — i.e. it behaves like "one long bounded single-shot."
A cron STARTS each window; the plugin ENDS it. Stagger the windows with
guard-bands so the two never overlap on the single GPU:
```
:00–:10  YOLO     cronjob('0 * * * *')   --continuous Y --interval 15 --max-runtime 600
:10–:20  guard-band (GPU free, absorbs model-load overrun)
:20–:30  BioCLIP  cronjob('20 * * * *')  --continuous Y --interval 15 --max-runtime 600
:30–:00  guard-band
```
Net: ~20 min/hour (~1/3) GPU use for both. ~40 frames/window at 15s sampling
restores detection coverage (vs the */10 collapse) while still sharing the GPU.

Implementation of `--max-runtime` (identical in yolo & bioclip, both default 0 =
forever so existing behavior is preserved):
```python
# before the while-loop, inside the Plugin() scope:
deadline = None
if args.continuous == "Y" and args.max_runtime > 0 and not using_image_dir:
    deadline = time.monotonic() + args.max_runtime
# at the loop TAIL, after the one-shot break, BEFORE time.sleep(interval):
if deadline is not None and time.monotonic() + args.interval >= deadline:
    logger.info("Max runtime reached — self-exiting to free the GPU")
    break
```
Check before sleeping (and add the interval) so it exits at the window edge
rather than overrunning by one interval.

GOTCHA — "max-runtime" is WALL-CLOCK, not inference time. The big model load
(BioCLIP ~28 GB ≈ 1+ min) happens INSIDE the window, so a 600s cap gives
BioCLIP only ~8–9 min of actual sampling (YOLO's smaller model gets ~full 10).
The GPU is HELD during load. If you need a clean 10 min of *inference*, bump
BioCLIP's `--max-runtime` to ~660–720 to absorb the cold start — but a literal
600s wall-clock cap is the safer default for guaranteeing windows don't drift
into each other.

CRITICAL FLOOR — a too-SHORT window publishes ZERO records (verified). When we
set the insect-bioclip window to `--max-runtime 120` (2 min, on the theory that
slow insects don't need long sampling), the window published NOTHING: 0 species,
0 uploads (confirmed via data API for that job over the :40–:42 window). The
~28 GB cold-start consumed essentially the entire 120s before the first
classify ran, so the plugin self-exited having sampled nothing. Bumping to
`--max-runtime 300` fixed it. LESSON: for a big-model plugin, `--max-runtime`
must be MODEL_LOAD + at least one full `--interval` with margin — never size the
window near the cold-start time. Practical floor for BioCLIP ViT-H/14 ≈ 240–300s
minimum even when the subject lingers; the limiter is model load, NOT subject
dwell time. Don't optimize the window DOWN toward the cold-start; optimize the
GPU schedule by giving slow-subject plugins a LESS FREQUENT cron (e.g. every 2h)
rather than a shorter per-run window.

How to verify frame count WITHOUT node access (Pete may decline kubectl/docker
mid-session): query the data API for the job's published records over the window
and count them — that IS the real frame count. Pod-log greps are fragile anyway
(pods get GC'd seconds after self-exit, and grep patterns may not match the
plugin's exact log wording — both bit us this session, yielding a false "0
frames" from logs while the data API was the source of truth).

**Scaling to N windows (adding a 3rd+ GPU plugin to the same node).** The
windowed pattern scales cleanly: an hour has six 10-min slots, so up to THREE
10-min GPU windows fit with a guard-band after each. Adding a new GPU plugin =
pick the next FREE slot and offset its cron, e.g. a third plugin on H00F:
```
:00–:10  YOLO              cronjob('0 * * * *')
:10–:20  guard
:20–:30  BioCLIP (birds)   cronjob('20 * * * *')   port 10000
:30–:40  guard
:40–:50  BioCLIP (insects) cronjob('40 * * * *')   port 10002   <- new
:50–:00  guard
```
Net ~30 min/hour for three windows. Keep every window flanked by a guard-band;
never schedule two GPU windows back-to-back (model-load overrun would collide).
Verify the new slot is genuinely free against ALL existing jobs' cron minutes
before submitting — `sesctl ... stat` to list them.

**Redeploying an EXISTING cataloged plugin to a new camera/sensor needs NO
rebuild and NO new catalog registration.** SES validates the *image*, not the
job/plugin name. So a second instance of bioclip pointed at a different camera
is just a NEW JOB YAML reusing the same `image:` tag (already cataloged +
sideloaded) with a different `--snapshot-url` and a free cron window. Steps:
1. Copy the existing job YAML; change `name:`, the plugin `- name:` (use a
   portal-searchable name like `insect-bioclip` so it's easy to find), the
   `--snapshot-url`, and the cron minute to the free slot.
2. (Optional but smart) curl the new camera URL FROM THE NODE first to confirm
   HTTP 200 + a valid JPEG before scheduling against a dead URL:
   `curl -s --max-time 10 "<snapshot-url>" -o /tmp/x.jpg -w "HTTP %{http_code} size=%{size_download}\n"; file /tmp/x.jpg`
3. Confirm the image tag is already sideloaded (`sudo k3s ctr images ls | grep <name>:<ver>`) — if so, skip build/catalog/sideload entirely.
4. `create -f <new.yaml>` → `submit -j <id>`. Done. (No `register-ecr-version.py`,
   no `docker build`, no sideload.)
Note: the H00F insect cam is the SAME Reolink RLC-811A as the hummingbird cam
but a different view served on PORT 10002 (hummingbird is 10000); creds are
still query-params.

**Resolution B — detector continuous + classifier one-shot/gated.** Run the
time-critical DETECTOR continuous (yolo — the watcher gates on its
`env.count.bird`), and the CLASSIFIER (bioclip) one-shot OR gated to run only
when the detector flags a bird (system-level, in the watcher). Simpler but the
classifier samples sparsely; prefer A when both models need real coverage.

**Three-way mode table to ship in DOCKER-BUILD.md** (Windowed / Continuous /
One-shot): Windowed = `--continuous Y --interval 15 --max-runtime 600` +
`cronjob('0 * * * *')`, best for "birds on a MEMORY-CONSTRAINED single-GPU node
shared with another model"; Continuous = always-on (fine on a big-unified-memory
node like Thor even alongside other GPU plugins — see §3(b); "needs a dedicated
GPU" is only true on small-VRAM nodes); One-shot = slow scenes OR when you want
self-healing + reboot survival (each tick is a clean pod).

## 3b. In-process fixed-period loop for a --continuous plugin (drift-free, skip-on-overrun)

When a plugin's OWN `--continuous <seconds>` loop drives cadence (not the SES
cron), the naive loop is wrong. Design a fixed-period grid so captures land on
`t0, t0+N, t0+2N, ...` and NEVER drift, and if a cycle OVERRUNS (slow/busy
camera, large image, capture timeout) the missed tick(s) are SKIPPED — no backlog.

Rejected naive loops:
- `capture(); sleep(N)` — DRIFTS: effective period = N + capture_time.
- `next += N` accumulator — on overrun `next` goes into the PAST → `sleep(0)`
  busy-loop / silent backlog.

Correct algorithm — monotonic grid with skip (~12 lines):
```python
N_ns  = interval_s * 1_000_000_000
start = time.monotonic_ns()          # MONOTONIC clock for scheduling
tick  = 0
while True:
    target = start + tick * N_ns
    now = time.monotonic_ns()
    if target > now:
        time.sleep((target - now) / 1e9)   # wait for this grid point
    do_one_capture_with_timeout()          # BOUNDED; warns+skips on timeout/error
    now = time.monotonic_ns()
    tick = (now - start) // N_ns + 1       # NEXT grid slot strictly in future
                                           #   -> missed ticks dropped, O(1)
```
Why safe: `tick` is RECOMPUTED from elapsed time every cycle, so an overrun of
any number of periods lands on the next future slot in one jump — no accumulator,
no backlog, no runaway. MONOTONIC clock → immune to NTP steps / DST / manual
clock-set (schedule on monotonic; STAMP the image with wall-clock `time_ns()`
separately — never conflate the two).

The other half of "no backlog" is a BOUNDED capture:
- Hard timeout on the grab (RTSP/HTTP). A slow/busy camera FAILS after the
  timeout instead of blocking forever.
- On timeout/error: log a WARNING and SKIP this sample; return. NO inline retry
  (a retry eats the next tick → overruns). Fail-SOFT: one bad frame must not kill
  a long-running process.
- Config rule (fail-FAST): capture timeout SHOULD be < interval. If
  `timeout >= interval`, overruns are expected (still safe via skip, just lossier)
  → WARN at startup.

CLI mode-flag shape (preferred over a single ambiguous flag like `--cronjob`):
two DESCRIPTIVE, MUTUALLY-EXCLUSIVE, REQUIRED flags via argparse
`add_mutually_exclusive_group(required=True)` — `--one-shot` (capture once, exit;
external SES cadence) and `--continuous <SECONDS>` (interval is the flag's
REQUIRED positive-int arg, so you can't run continuously without an interval and
can't set an interval in one-shot). Both/neither or interval<=0 → fail-fast parse
error, no silent default.

## 4. Two job files per camera plugin — let students choose the mode

Ship BOTH variants and a decision table in DOCKER-BUILD.md:
- `jobs/<plugin>-<node>.yaml`         → continuous (`schedule(...): True`)
- `jobs/<plugin>-<node>-oneshot.yaml` → cron (`schedule(...): cronjob(...,'*/10 * * * *')`)

The continuous science rule is `schedule(<plugin>): True` (no `cronjob()`); the
plugin's own `--continuous Y --interval N` loop drives the cadence.

Switching modes on a running job: `sesctl ... rm -s <id>` (suspend) then
`sesctl ... rm <id>` (remove), then `create -f <other-file>` + `submit -j <new-id>`.

## 5. Windowed-cron jobs only launch AT the cron minute — plan verification around it

A windowed plugin whose science rule is `cronjob('...', 'M * * * *')` launches
its pod ONLY at exactly minute M of each hour. If you submit at :22 but the rule
is `'20 * * * *'`, this hour's window is already gone — the next launch is
M next hour (~58 min away). The job is correctly "Running" in `sesctl stat`, but
no pod fires and the data plane stays empty until the next tick. This is NORMAL,
not a deploy failure — don't go diagnosing a "crash."

Implications for a deploy + verify pass:
- **To verify a windowed job fast, target the NEXT plugin whose cron minute is
  soonest.** When cutting over multiple windowed jobs (e.g. bird `'20'` + insect
  `'40'`), submit them, note the current minute, and verify against whichever
  window arrives first rather than waiting on the one you just missed.
- During a version cutover, keep the OLD job SUSPENDED (`rm -s`, not `rm`) as a
  one-command rollback until the NEW version is confirmed publishing in the data
  plane at the new tag. Only `sesctl rm <old-id>` once verified.
- Cutover sequence that works: `rm -s <old>` ×N → `create -f <new.yaml>` →
  grab the returned numeric job id → `submit -j <new-id>` → confirm `stat` shows
  the new ids Running and the old ones Suspended → wait for the soonest cron
  window → verify in the data API (tag == new version, expected topics present).
- If you can't wait for the natural window, a one-shot manual run proves the
  image but touches the GPU outside the schedule — Pete generally prefers
  scheduler-managed proof, so default to waiting for the real window.
