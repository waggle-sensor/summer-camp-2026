# WES plugin shared filesystem + producer/consumer cache architecture

How Waggle Edge Stack (WES) plugin pods share files on a node, and the
CPU-producer / GPU-consumer pattern that shared cache unlocks. Confirmed on Thor
node H00F (2026-07) against edge-scheduler 0.28.0 source
(`pkg/nodescheduler/resourcemanager.go`).

## 1. Does WES give plugins a shared, persistent, cross-pod filesystem? YES.

By default each plugin runs as its own k3s pod with its own container FS — pod A's
files are invisible to pod B. But WES bind-mounts host paths into plugin pods, and
host-backed files ARE cross-pod visible and survive pod/node restart.

### Automatic uploads mount (every plugin gets it)
WES injects into EVERY plugin pod:
```
host  /media/plugin-data/uploads/<JOB>/<NAME>/<TAG>
pod   /run/waggle/uploads          (read-write)
```
- Backed by the node root disk (H00F: /dev/nvme0n1p1, 937G) → **persists across
  pod restart AND node reboot**. Not pod-ephemeral.
- Already structured **per-plugin-instance** on disk (e.g.
  `bioclip-species-classifier-5647/`, `birdnet-species-5645/`).
- Because it's a hostPath, a file one pod writes under `/run/waggle/uploads`
  lands on the host under `/media/plugin-data/uploads/...`, and **any other pod
  mounting the same hostPath reads it** — this is the cross-plugin sharing
  mechanism.
- **Caveat:** this tree is watched by `wes-upload-agent` (host
  `/media/plugin-data/uploads` → `/uploads`). Do NOT put a *local-only* cache
  here unless you've confirmed the agent only uploads pywaggle-staged files, not
  everything under the mount. Prefer a dedicated subtree for local-only data.

### Explicit user volumes
WES supports user-declared volumes (`uservolume-N`), BUT the scheduler source
warns they **require a nodeSelector or the pod fails to schedule**. Arbitrary
hostPath is possible but gated; the automatic uploads mount is the low-friction
path.

### Other injected context (useful to a plugin)
`WAGGLE_APP_ID` (= pod uid), `HOST` (= node name), `WAGGLE_PLUGIN_HOST/PORT`,
a mounted `/run/waggle/data-config.json`. Pod spec: `ShareProcessNamespace=true`,
ServiceAccount `wes-plugin-account`, `RestartPolicy: Never`, finished pods GC'd
after 60 s (`ttlSecondsAfterFinished`). Jobs do not retry (`backOffLimit=0`).

### How to inspect on a node (read-only)
```bash
ssh USER@node-<VSN>.sage    # NOT bare H00F
# list host shared area
sudo ls -la /media/plugin-data/          # uploads/ docker_registry/ system-metrics/
# how a pod mounts it (system pod always present):
sudo k3s kubectl get pod -n default <wes-upload-agent-pod> -o json \
  | python3 -c "import sys,json;d=json.load(sys.stdin);[print(v) for v in d['spec']['volumes']]"
```
NOTE: plugin pods only exist AT their cron minute (windowed jobs) — none may be
running when you look. Read the edge-scheduler source for the authoritative pod
template instead of waiting for a pod.

## 2. Producer/consumer cache architecture (the GPU-sharing win)

**Decouple acquisition (cheap, CPU, continuous) from inference/upload (expensive,
GPU/network, bursty).** A CPU sampler fills a shared ring cache continuously;
separate consumer plugins wake on their own schedule, read the cache, act, and
upload only what matters.

### Why it beats "GPU plugin samples the camera itself"
The single-GPU contention trap (see
`scheduling-continuous-vs-oneshot-and-gpu-contention.md`): two always-on GPU
plugins can't co-run on one Thor GPU. A `load→infer→exit`-per-image pattern also
pays the full model-load cost every image and holds the GPU the whole time.

**Batched consumer** loads the model ONCE, infers N cached images, uploads the
interesting ones, unloads, FREES the GPU. Amortization (BioClip ViT-H/14, load
~10.4 s, inference ~1 s/img):
- per-image `load→infer→exit`: 10.4 + 1 = 11.4 s/img, GPU held throughout,
  ~5 img/min ceiling.
- batched N=10: 10.4 + 10×1 = 20.4 s for 10 = **~2.04 s/img** amortized, GPU held
  20.4 s then **freed** (~5.6× throughput, GPU idle/shareable the rest of the
  window).

Net: YOLO / BioClip / BirdNet each load → drain the cache → unload; the CPU
sampler is the shared producer feeding all of them.

## 3. Shared ring-cache design rules (from image-sampler2)

- **Producer never uploads.** Continuous mode is local-only; uploading is a
  consumer concern. Keeps the producer single-purpose and composable.
- **Uniqueness via a stable, user-supplied name**, NOT the SES job id (changes
  every resubmit, unpredictable to a consumer) and NOT an opaque hash. Path shape:
  `<SHARED_ROOT>/<cache-name>/<camera>/`. Consumers reference a known cache-name.
- **Per-stream subdirs** (one dir per camera/stream) = independent, race-free
  rings; each `--stream` is its own process, so a shared dir would race.
- **Bounded ring:** cap by count AND/OR size (decimal MB), evict-on-either, at
  least one cap required. Evict oldest-first by the capture-ts prefix in the
  filename (authoritative order, no stat).
- **Stateless management:** scan the dir each write; crash-safe, restart re-scans.
- **Evict BEFORE the atomic write joins the ring:** write `.tmp` → fsync →
  `os.replace` to final name; only the final-named file counts. Ring never
  transiently exceeds caps; no torn file ever joins it.
- **Oversized new image** (bigger than the whole size cap even with empty ring):
  drop the NEW image with a warning, keep the cache valid.
- **Fail-soft** on eviction-delete/disk-full (warn, skip, keep looping);
  **fail-fast** on config errors (missing cache-dir, no cap, flag misuse).
- **Startup adoption:** adopt files matching the name pattern; leave unknown files
  untouched and uncounted; never wipe.

## 3b. Two-layer cache model + the /local-cache WES component (2026-07)

`/uploads` (cloud-bound, transient, drained+deleted by wes-upload-agent) does NOT
serve on-node producer→consumer sharing. For that, add a dedicated shared node
cache `/local-cache` (host `/media/plugin-data/local-cache`, sibling of uploads),
managed by a NEW WES DaemonSet `wes-local-cache-manager` modeled directly on
`wes-upload-agent`. A shared cache anyone can write to needs a disk bound or one
buggy plugin fills the node — so split responsibility into TWO layers:

- **Layer 1 = policy, in the PLUGIN.** Graceful, semantics-aware eviction (newest-N,
  MB budget, LRU rows, per-camera). Only the plugin knows what its data MEANS. This
  is the ring in §3. Keeps a well-behaved plugin far under its cap.
- **Layer 2 = blunt backstop, in the DaemonSet.** Semantics-free. Periodic sweep
  enforces two byte caps by deleting OLDEST-FIRST, and only ever fires against a
  cache unit that has ALREADY blown past its allocation (a misbehaving plugin). A
  well-behaved plugin is NEVER touched by Layer 2.
  - per-UNIT cap (`<namespace>/<plugin>`, default 2 GiB) → isolation: one greedy
    plugin starves only itself.
  - per-NODE cap (default 15 GiB) → outer ceiling; this pass also mops up stray
    files outside any unit.
- WHY a filesystem sweep, not a k8s quota: `/local-cache` is a hostPath shared
  across pods; kubelet ephemeral-storage accounting does NOT track hostPath bytes
  and emptyDir sizeLimit doesn't apply. A periodic sweep is the only portable bound.

### Fail-fast, never silent-fallback, on a shared resource
A producer that expects `/local-cache` but runs on a node lacking the component
(or started without the `-v host:/local-cache` mount) must FAIL FAST with an
explanation — NOT silently fall back to pod-ephemeral `/tmp`, which "works" but
writes frames no consumer can ever read. That silent fallback was scaffolding good
for early dev and a footgun for students/production; remove it once the real mount
exists. Resolve `--cache-root > $IS2_CACHE_ROOT > /local-cache`, then assert the
resolved root is an existing writable dir or exit config-error. Keep `--cache-root`
as an explicit escape hatch for off-node dev. (Don't over-engineer a `--require`
flag: if the shared cache is the only sane target, requiring it IS the behavior.)

### Production-hardening checklist for a sweep DaemonSet on a 1777 shared dir
The cache dir is world-writable+sticky (1777, so differing-UID pods each own a
subtree and read across them). That makes the sweeper security-sensitive:
- **Symlink safety.** A plugin can plant a symlink. Use `os.lstat` (never follow),
  skip non-regular files (`stat.S_ISREG`), and prune symlinked subdirs from
  `os.walk(..., followlinks=False)`. Otherwise a symlink at another plugin's tree
  or `/etc` gets stat'd/counted/traversed. `os.remove` on a symlink only unlinks
  the link (safe), but the WALK is the exposure.
- **Cap-sanity fail-fast at startup.** A ConfigMap typo `PER_NODE_MAX_BYTES: "0"`
  would make every sweep evict the ENTIRE cache. `validate_config()` must refuse to
  start (SystemExit → loud CrashLoopBackOff) on any non-positive cap/interval/depth
  or `per_node < per_subdir`. `_env_int` must reject non-numeric (`"2Gi"`) with a
  bytes-only message — env values are plain bytes, no k8s suffixes.
- **Liveness = health-file touch/rm.** Sweeper touches `/tmp/healthy` each sweep;
  livenessProbe `rm /tmp/healthy` — a stuck loop can't recreate it → restart (same
  pattern as wes-upload-agent). `RUN_ONCE=1` env for a single-pass test/manual run.
- **DRY_RUN=1** logs evictions without deleting — the recommended first-fleet
  rollout: canary node in DRY_RUN, watch logs a day, then enable real eviction.

### Repo shape for a WES component headed to CI review
- **Split the manifest:** `kubernetes/<name>.yaml` = PRODUCTION (no nodeSelector,
  registry image, DRY_RUN note) + `kubernetes/test/<name>.test.yaml` = test overlay
  (side-loaded image name `docker.io/library/...:test`, node pin COMMENTED OUT by
  default so it works on any single-node cluster unedited — don't hardcode a
  hostname an admin MUST delete). A reviewer must be able to see the prod shape.
- **`make test` self-bootstraps a venv** (`python3 -m venv .venv && pip install
  pytest`) so it runs on a clean checkout with no ambient pytest. PITFALL: a green
  run riding on a leaked venv from another project hides that a CI reviewer's clean
  box has no pytest — always verify from a fresh shell / `rm -rf .venv` first.
- **`.dockerignore`** keeps `.venv/.git/.pytest_cache/tests/` out of the build.
- **Unit-test the sweep logic** (pure helpers: unit-discovery, files-by-age,
  evict, sweep passes, DRY_RUN deletes nothing, symlink skip, config validation).
  "Verified once live" is not repeatable coverage a reviewer can run.
- **HANDOFF.md** = review checklist: what's done/verified vs CI-owned (publish
  image, node provisioning in ansible, kustomize fold-in, cross-user-read confirm).
- Fix dangling `../foo.md` doc links that point OUTSIDE the git repo (workspace
  design docs aren't in the cloned tree). Manifest `../sibling.yaml` refs are fine.

## 4. Ring ↔ trigger consumer behavior (POSIX-safe)

- **Size the cache ≥ longest trigger lookback.** A trigger consumer usually wants
  frames from N seconds BEFORE the event (e.g. 10 s pre-roll). Ring evicts
  oldest-first, so hold ≥ (max_lookback / sample_interval) images with margin.
- **Concurrent read + evict is safe:** a consumer with an OPEN fd keeps the inode
  even if the ring unlinks the file (POSIX). Atomic writes mean no partial reads.
- **Consumers must tolerate ENOENT/TOCTOU:** a listed path may be evicted before
  open — treat ENOENT as "already gone, skip"; copy/upload promptly.
- Sampler and consumers do NOT coordinate (no locks). Consumers are read-only;
  only the sampler writes/evicts its own ring.

## 5. Composable CLI shape that supports this (image-sampler2)

- `--one-shot` / `--continuous <sec>` — two descriptive, mutually-exclusive,
  REQUIRED mode flags (argparse `add_mutually_exclusive_group(required=True)`).
  See `scheduling-continuous-vs-oneshot-and-gpu-contention.md` §3b for the
  drift-free fixed-period loop.
- `--from-cache <dir>` — source flag orthogonal to mode. `--one-shot --from-cache`
  uploads the newest cached image via the existing upload path (no camera hit, no
  new upload logic). This is how a periodic-snapshot job is built by COMPOSITION
  (a second SES-cron one-shot job) rather than adding upload behavior to the
  producer. One-shot-only; fail-fast if combined with `--continuous` or empty
  cache. Time-window selectors (`--closest-before/after-timestamp <ns>`) are a
  planned enhancement for cloud-side "pull the frame nearest time T".
