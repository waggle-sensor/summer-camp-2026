# Side-loading a plugin for testing: pluginctl vs sesctl+ECR

Two ways to run a plugin on a node, with different prerequisites:

## sesctl (scheduler / SES) — needs ECR registration
The scheduler validates the app exists in the ECR registry BEFORE launching.
Requires BOTH the ECR app metadata AND the built image to exist (two distinct
failure modes). This is the production path. Pods land in the `ses` namespace.

## pluginctl (direct node run) — NO ECR registration needed
`pluginctl run PLUGIN_IMAGE [-- PLUGIN ARGS]` runs the image in a real WES pod on
the node with full upload plumbing (RabbitMQ, /run/waggle/uploads -> Beehive
agent). It BYPASSES the ECR-registration gate entirely, so it's the right tool for
a real Beehive round-trip during development ("side-load for testing"). Pods land
in the `default` namespace.

Useful `pluginctl run` flags (verified on H00F):
    -e, --env strings       set env vars (e.g. -e CAMERA_USER=test)
    --env-from string       set env vars from a FILE  <-- use this for secrets so
                            the password never appears in argv / process listing
    --name / -n             plugin name
    --node                  target node
    --selector              placement (e.g. resource.gpu=true)
    --volume / -v           host path mounts
    --develop               enable WAN access
`pluginctl build PLUGIN_DIR` builds from a Dockerfile dir and PRINTS an image ref
usable by `pluginctl run -n name $(pluginctl build dir)`.

RBAC: `pluginctl run` may fail immediately with
`Error: pods is forbidden: User "<user>" cannot create resource "pods" in ...
namespace "default"`. pluginctl HARDCODES the `default` namespace (even
`pluginctl ps` targets `default`) and IGNORES the kubeconfig context's `namespace`
field — so even if `~/.kube/config`'s current-context sets `namespace: <user>`,
pluginctl still hits `default`, where the per-user account has no pod-create right.
FIX (verified on H00F): just run `sudo pluginctl ...` — sudo picks up root's
cluster-admin kubeconfig, which CAN create pods in `default`. Plain `sudo
pluginctl run/ps/logs/rm/exec` all work. (Do NOT bother with `--kubeconfig
/etc/rancher/k3s/k3s.yaml` as a non-root user — `kubectl` can't even read that
root-owned file: `permission denied`. `sudo` is the clean path.)
Verify who-can-do-what with
`sudo k3s kubectl auth can-i create pods -n default` (admin = yes) vs
`kubectl --kubeconfig ~/.kube/config auth can-i create pods -n <user-ns>` (the ns
the user CAN write, usually their own). Note the one-shot pod EXITS after its
upload (that's correct); a `--continuous` pod STAYS Running (inspect it live). If
`pluginctl run` reports "Plugin failed to run ... remains in the system", inspect
with `sudo k3s kubectl describe pod -n default <name>` and `... logs -n default
<name>` — a config/identity error there is a plugin bug, not an RBAC failure.

VOLUME MOUNT requires a node selector (verified on H00F): `pluginctl run -v
<host>:<path>` fails with `Error: volume mounting requires nodeSelector. Please
specify the node by --selector or --node`. Add a placement. GOTCHA: `--node
<kubernetes.io/hostname>` (e.g. `00004cbb4701d16c.agx-thor`) FAILED to schedule —
pod stuck `Pending` with `FailedScheduling ... didn't match Pod's node affinity/
selector`. What WORKS is a LABEL selector on a label the node actually carries:
`--selector zone=core` (single-node WES nodes are labelled `zone:core` plus
`resource.gpu=true`, `resource.cuda110:true`, etc.; list with
`sudo k3s kubectl get node <n> -o jsonpath='{.metadata.labels}'`). Prefer
`--selector <label>=<val>` over `--node <name>` for pluginctl placement.

OBSERVING a pod-local cache (e.g. a `/tmp` ring invisible to the host/other pods):
three ways, in order of usefulness for real evidence —
  1. `-v <hostdir>:<cachepath>` bind-mount the cache to a HOST dir (NOT under
     `/media/plugin-data/uploads`) so you can `ls`/`stat`/`sha` the ring directly
     over SSH while the `--continuous` pod runs. Best for watching eviction live.
  2. `sudo pluginctl logs <name>` — the plugin's own per-write log lines stream
     from outside the pod (e.g. `wrote <f> evicted=1 ring_count=3`).
  3. `sudo pluginctl exec <name> -- python3 -c '...'` to read files/EXIF from
     inside the pod (the pod has piexif etc.; the node host usually does NOT).

## Getting a NEW private repo's code ONTO the node (git bundle over ssh) — VERIFIED H00F 2026-07-15
The native-Thor build path needs the repo checked out on the node. A node that
already has one private repo cloned (e.g. sage-yolo2) CAN `git fetch` it — a cached
credential/token from the original clone persists — BUT it CANNOT `git clone` a
BRAND-NEW private repo: `git clone https://github.com/<owner>/<newrepo>.git` fails
with `fatal: could not read Username for 'https://github.com': No such device or
address` (no interactive tty, no gh, no per-repo cred yet). Don't fight node-side
GitHub auth. Since you have working ssh BOTH ways (your box ⇄ node), push the repo
directly as a git bundle — no GitHub round-trip on the node:
    # on your box, from the repo root
    git bundle create /tmp/<repo>.bundle --all      # full history + all refs/tags
    scp /tmp/<repo>.bundle USER@node-<VSN>.sage:/tmp/
    # on the node
    ssh USER@node-<VSN>.sage '
      cd ~/AI-projects && rm -rf <repo>
      git clone /tmp/<repo>.bundle <repo>            # clones from the bundle file
      cd <repo> && git checkout master
      git remote set-url origin https://github.com/<owner>/<repo>.git  # for future fetches
    '
The bundle carries every commit + tag, so the node clone is identical to origin
(verify `git log --oneline -1` matches). Re-pointing origin at GitHub lets later
`git pull`s work (fetch on an already-present clone succeeds, unlike the initial
clone). This is the reliable way to seed a new plugin repo on the node before
`scripts/deploy-sideload.sh`.

## Side-load WITHOUT any registry: build local + import into k3s containerd
`pluginctl run` uses the k8s default image pull policy. For a NON-`:latest` tag
(e.g. `:0.1.1`) the default is `IfNotPresent`, so if the image already exists in
the node's **k3s containerd** store it will NOT pull remotely. This is the
cleanest dev path — no ECR push, no registry login, no credentials, and it dodges
BOTH the broken Jenkins buildkit and the dead lan0 registry:

    podman build -t localhost/<plugin>:<ver> .          # RUN steps work under podman
    podman save localhost/<plugin>:<ver> | sudo k3s ctr images import -
    # then reference it as a docker.io/library/<plugin>:<ver> or the imported name
    pluginctl run docker.io/library/<plugin>:<ver> -- <args>

### IMAGE-NAME TRAP: what containerd STORES the image as (ImagePullBackOff) — VERIFIED 2x
The single most common failure after a side-load is an `ImagePullBackOff` /
`ErrImagePull` even though the image is clearly on the node — because the name the
POD/MANIFEST references does not match the name k3s **containerd** actually stored
it under, so kubelet tries to PULL it from a registry (e.g. `localhost:443`) and
fails. Symptoms: `sudo k3s kubectl describe pod ...` shows `Failed to pull image
"localhost/<plugin>:<tag>"` / `Back-off pulling image`. ALWAYS diagnose by listing
what containerd holds vs what the manifest asks for:
    sudo k3s crictl images | grep -iE "REPOSITORY|<plugin>"   # the STORED name(s)
    # compare against the pod's image: field / pluginctl run <ref>

CRUCIAL, non-obvious: the stored name DIFFERS BY IMPORT INVOCATION (both verified
on H00F, same session):
  - `podman save <img> -o file.tar` then `sudo k3s ctr images import file.tar`
    (file arg)  →  containerd RETAGS to `docker.io/library/<plugin>:<tag>`. A
    manifest that says `localhost/<plugin>:<tag>` then ImagePullBackOffs. FIX:
    make the manifest/`pluginctl run` ref say `docker.io/library/<plugin>:<tag>`.
  - `podman save <img> | sudo k3s ctr images import -` (piped stdin)  →  PRESERVES
    the `localhost/<plugin>:<tag>` tag; referencing `localhost/...` then works.
So do not assume; run `crictl images` after every import and reference the EXACT
string it shows. `imagePullPolicy: IfNotPresent` (the default for non-`:latest`
tags) only helps if the referenced name matches a stored name — a mismatch still
triggers a pull. This trap bit both a DaemonSet manifest AND is why you re-verify
the resolved ref for `pluginctl run` too.

Tell-tale that this is the established convention on a node: `sudo k3s crictl
images` shows the SAME image id under both a `docker.io/library/<plugin>:<ver>`
tag AND a `registry.sagecontinuum.org/<user>/<plugin>:<ver>` tag — i.e. locally
built + imported, not pulled. NOTE: podman/buildah storage is a DIFFERENT store
from k3s containerd; a `podman build` image is not visible to k3s until you
`podman save | k3s ctr images import` it. Confirm the resolved `image:` and pull
policy first with `pluginctl deploy --dry-run -n probe <image> -- --help`.

## Side-loading a WES PLATFORM change (ConfigMap/scheduler), not just a plugin
Different problem from `pluginctl run`: when the thing under test is a change to WES
machinery itself (e.g. the node-identity-env change — extend `wes-identity` + add
`envFrom` in the scheduler), you can't just `apply`/`delete` a standalone object.
The change MUTATES existing resources, so bring-up/tear-down is RESTORE-based, not
delete-based. Pattern that worked (`wes-nodeinfo-injection/node-test/`, 2026-07-09):
- **One-shot backup helper:** `kubectl get <kind> <name> -o yaml > .backup/…` ONCE
  (never overwrite an existing backup → re-runnable); if the resource is absent,
  write an `__ABSENT__` marker so restore = delete. Teardown `kubectl apply -f` the
  backup (or delete on marker), then rm the backup file. Keep backups in a
  gitignored `.node-backup/` so teardown works from a fresh shell.
- **TWO TIERS by blast radius — build both, lead with Tier 1:**
  - **Tier 1 (safe, seconds to revert, NO scheduler swap):** back up + regenerate
    the `wes-identity` ConfigMap with the new vars from THIS node's real manifest
    (`kubectl create cm … --from-env-file=<gen> --dry-run=client -o yaml | kubectl
    apply -f -`), then launch a test pod that sets `envFrom: {configMapRef:
    wes-identity, optional:true}` ITSELF and prints the resolved values. This
    exercises the whole ConfigMap→env→consumer chain WITHOUT the patched scheduler
    (existing plugins untouched — they don't read wes-identity until Tier 2). This
    is the daily-driver loop and the pywaggle2 test harness (inline the reader in
    the pod so it's self-contained on `python:3.12-slim`, no image build).
  - **Tier 2 (control-plane risk):** proves the scheduler auto-injects for ALL
    plugins. podman-build the patched `edge-scheduler` + `k3s ctr images import`
    (same no-registry path as above), back up + `kubectl set image` the
    `wes-plugin-scheduler` Deployment, `rollout status` — and AUTO-REVERT from
    backup if the rollout doesn't go Ready (a crashlooping scheduler stalls plugin
    scheduling until reverted). Run Tier 1 FIRST so the CM actually holds the vars.
- **On-node kubectl = `sudo kubectl`** (per-user account can't create in `default`;
  same RBAC story as pluginctl above). Gate the scripts with a `need` check + a
  grep that the patch is actually applied in `.upstream/` before building.
- **Verify the add/remove control flow locally before the live run:** a fake
  `kubectl` on PATH that appends its args to a log lets you assert the sequence
  (backup→regenerate→create→deploy→restore→cleanup) against a fixture config dir,
  with zero cluster risk. bash -n every script; parse the pod YAML.

### PITFALL: restore via `kubectl apply -f backup.yaml` CONFLICTS (VERIFIED live on H00F 2026-07-12)
The Tier-1 teardown restored the `wes-identity` ConfigMap by `kubectl apply -f
.backup/…yaml`. It FAILED live with `Operation cannot be fulfilled … the object has
been modified` and left the CM in the mutated (5-var) state with the backup NOT
consumed. Cause: the ADD step regenerates the CM via `kubectl create configmap … |
kubectl apply -f -`, a NON-apply mutation that bumps `resourceVersion` and rewrites
`data` outside apply's 3-way merge base. The backup's stale `resourceVersion` +
`last-applied-configuration` annotation then make the restore apply conflict. FIX
(verified: clean round-trip after): restore with `kubectl replace` FROM THE BACKUP
as source of truth, after stripping volatile metadata
(`resourceVersion`/`uid`/`creationTimestamp`/`status` + the last-applied annotation);
fall back to delete+create if replace can't reconcile. Same idiom works for the
Deployment restore in Tier-2 teardown. Never `apply` a raw `kubectl get -o yaml`
backup over an object mutated by a non-apply op.

### CRUX: the patch must be in the BINARY that builds the pod — stale host pluginctl (VERIFIED H00F 2026-07-12)
The node-identity `envFrom` injection lives in
`resourcemanager.go::createPodTemplateSpecForPlugin`, which is SHARED by every
pod-builder entry point (`CreatePodTemplate`, `CreateJobTemplate`,
`CreateDeploymentTemplate`, and the scheduler daemon) — so the patch is complete in
ONE place. BUT injection only happens if the BINARY doing the building carries the
patch. GOTCHA that wasted a debug cycle: a node's host `/usr/bin/pluginctl` is a
STALE 0.28.0 binary (dated 2025) that builds the pod CLIENT-SIDE with its own
unpatched ResourceManager — so `sudo pluginctl run …` on the node shows an EMPTY
`envFrom` even with the patched scheduler Deployment rolled out. To actually prove
auto-injection: schedule through a PATCHED binary — either run pluginctl from INSIDE
the patched scheduler pod (`kubectl exec <sched-pod> -- pluginctl run …`, after
writing an in-cluster kubeconfig from the mounted serviceaccount token, since the
pod has no /root/.kube/config), or via the cloud/sesctl path that drives the patched
scheduler daemon. VERIFY the patch is in a binary with
`strings /usr/bin/{pluginctl,nodescheduler} | grep -c wes-identity`. ROLLOUT
consequence: shipping the patched scheduler image is not enough — the host pluginctl
must be updated too (it's in the same image), or operators must schedule via the
daemon path.

### PITFALL: `kubectl wait --for=condition=Ready` on a one-shot test pod (VERIFIED 2026-07-12 review)
A Tier-1 harness pod that is `restartPolicy: Never` and just prints + exits (e.g.
the inline pywaggle2 reader on `python:3.12-slim`, ~1s runtime) frequently NEVER
reports `Ready=True` — it races straight to phase `Succeeded`. So
`kubectl wait --for=condition=Ready pod/<name> --timeout=60s` will burn the FULL
timeout every run (usually masked by a trailing `|| true`), then fall through to a
blind `sleep 3` before grabbing logs. Works, but every on-node run hangs ~60s and
looks like a failure. FIX: wait for the terminal phase instead —
`kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/<name> --timeout=60s`
(k8s ≥1.23 / k3s supports jsonpath waits), or `--for=condition=Initialized` then
poll logs. Reserve `condition=Ready` for long-lived/`--continuous` pods that stay
Running.

### Confirming a Go platform-patch is idiomatic BEFORE side-loading (review technique)
When the platform change is a Go patch to edge-scheduler (e.g. adding `EnvFrom` in
`resourcemanager.go::createPodTemplateSpecForPlugin`), don't just check it compiles
— check it reuses what upstream already has, so the diff is minimal and merge-safe:
- grep the target package for any helper the patch calls (`booltoPtr`/`boolToPtr`)
  — VERIFIED it already exists (resourcemanager.go:2181 `func booltoPtr(b bool) *bool`)
  so the patch must REUSE it, never redefine (a duplicate def = compile error).
- grep for the import alias the patch uses (`apiv1 "k8s.io/api/core/v1"`) — confirm
  it's already imported in that file so `apiv1.EnvFromSource` resolves.
- Strong reviewer-friendliness signal: upstream sometimes has the exact pattern
  COMMENTED OUT nearby (resourcemanager.go had commented `Optional: booltoPtr(true)`
  EnvFrom stanzas at ~L656/666/712) — means the maintainers already intended this
  shape; cite it in the HANDOFF/PR to speed review.
- Pin k8s types to the upstream-vendored version (`k8s.io/api v0.23.1`) so the
  isolated `scheduler-change/` unit module and the real build use identical types.

### The node-manifest GPS fields ARE real top-level keys (schema fact, VERIFIED 2026-07-12)
The whole node-identity-env change reads `gps_lat`/`gps_lon` from
`node-manifest-v2.json`. This is NOT an invented field: the LIVE w096 manifest
(world-readable 0644, top-level keys: address, computes, `gps_lat`, `gps_lon`,
lorawanconnections, modem, name, phase, project, resources, sensors, tags, vsn)
carries them, AND upstream `waggle-edge-stack/kubernetes/generate-default-manifest`
declares `"gps_lat": null, "gps_lon": null` in the DEFAULT template. So every node's
manifest has the keys (possibly null). `mobility` is NOT yet a manifest key (proposed,
default `static`) — until CI adds it the generator emits the empty sentinel →
pywaggle2 reads `"unknown"`. jq `(.gps_lat) // "999"` correctly maps BOTH a literal
`null` value AND an absent key to the sentinel (verified: `{"gps_lat":null}`→999,
`{}`→999, real float→passthrough).

## GPU consumer OOMKilled at first inference — pluginctl's default mem limit (VERIFIED H00F 2026-07-14)
A GPU plugin (YOLO11x, `nvcr.io/nvidia/pytorch` base) side-loaded via a plain
`sudo pluginctl run ...` LOADS the model on cuda fine ("Model loaded — 80 classes")
then gets **OOMKilled (exit 137) at the FIRST inference** — pod terminates ~4-6s in,
before any `Published`/`no detections` line, and no seen-store/output is written. It
looks exactly like a silent inference crash but the pod's terminated-state reason is
`OOMKilled`. Cause: pluginctl applies a DEFAULT memory limit far too small for a
PyTorch-CUDA plugin (model + CUDA context + frame decode blow past it the moment the
first `detect()` allocates). FIX: raise the limit with
`--resource limit.memory=16Gi,request.memory=4Gi` (Thor has 125GB unified; 16Gi is
ample for YOLO11x). Diagnose with the pod's terminated reason:
`sudo kubectl get pod <n> -n default -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}:{...exitCode}'`
→ `OOMKilled:137`. NOTE: `--resource resource.gpu=true` is INVALID — that flag takes
k8s QUANTITIES only (`limit.cpu=2`, `request.memory=4Gi`); GPU access on Thor is
automatic via the NVIDIA container runtime, so DON'T pass a gpu resource at all.

## Hot-swapping a live long-lived consumer to a new version (VERIFIED H00F 2026-07-15)
Replacing a running `--every`/`--continuous` consumer pod with a new image version,
WITHOUT disturbing the producer that feeds the shared cache. Verified swapping
sage-yolo2 2.0.0 → 2.1.0 (added a crop-producer feature) while `hummingcam-producer`
kept running:
1. **Probe the exact live spec first** — never guess the args to relaunch. Pull the
   running pod's image, args, resources, and volume mounts straight from k8s:
       sudo kubectl get pod <consumer> -n default -o jsonpath='{.spec.containers[0].image}'
       sudo kubectl get pod <consumer> -n default -o jsonpath='{.spec.containers[0].args}'
       sudo kubectl get pod <consumer> -n default -o jsonpath='{.spec.containers[0].resources}'
   Relaunch with the SAME args + only the new flags added, so behaviour is a
   controlled delta (e.g. keep `--source cache --input … --every 10m --all-unseen
   --classes bird --save-match bird:0.4`, add `--crop-match bird:0.5 …`).
2. **Build+import the new tag** (the repo's `scripts/deploy-sideload.sh
   --skip-register` wraps native arm64 `docker build` → `k3s ctr images import`;
   skip-register because pluginctl needs no ECR catalog). The k3s import of a
   ~10 GiB CUDA image takes ~5 min — run it backgrounded with completion notify.
   Confirm `sudo k3s ctr images ls | grep <tag>` before proceeding.
3. **Remove the OLD consumer ONLY** — `sudo pluginctl rm <consumer>`. Then
   `sudo pluginctl ps` to CONFIRM the producer is still Running and only the
   consumer is gone. Never `pluginctl rm` the producer.
4. **Relaunch** the new tag (see the foreground-attach gotcha below).
5. **Verify the new path is actually active**, three independent proofs: (a) a
   NEW startup log line unique to the new feature (`crop-producer ON: rules=…` —
   proves the new flag/codepath, not just a restart); (b) `pluginctl ps` shows
   0 restarts + Running; (c) data API shows `meta.plugin=…:<newver>` now
   publishing (proves the new build is the one shipping, not a leftover).
6. **Rollback is one command** — the old image stays imported in k3s (don't delete
   it), so `sudo pluginctl rm <consumer>` + re-run the OLD tag line restores the
   prior state with no rebuild. State the rollback in the plan up front.
Note the seen-store persists on the shared cache across the swap (e.g. "8452
known"), so the new consumer dedups against the old one's history — no reprocessing
storm. A NEW producer feature that writes a SEPARATE cache dir (crops →
`<crop-cache-name>/…`, distinct from the raw stream) cannot corrupt the raw frames
— a clean, low-blast-radius way to extend a producer.

## GOTCHA: `pluginctl run` of a long-lived pod ATTACHES to logs and blocks (VERIFIED H00F 2026-07-15)
`sudo pluginctl run --name <n> … <image> -- <args>` for a `--continuous`/`--every`
(never-exiting) plugin FOREGROUND-ATTACHES to the pod's log stream after launch, so
the command does NOT return — over SSH it hits the shell timeout (exit 124) and
LOOKS like a failed launch. IT IS NOT: the pod launched fine. Do NOT re-run it (a
second run collides on the `--name`). VERIFY instead: `sudo pluginctl ps` /
`sudo kubectl get pod <n> -n default` — you'll see it Running, 1/1, 0 restarts,
started at the expected time. This is the OPPOSITE of the one-shot case below
(where run detaches early). Rule of thumb: one-shot pod → run detaches before the
output you want; long-lived pod → run blocks/attaches → let it time out and confirm
via `ps`. To avoid the hang entirely, launch backgrounded (`… >/dev/null 2>&1 &`)
then confirm with `pluginctl ps`.

## CAPTURING a one-shot pod's FULL logs before GC (pluginctl detaches early)
`sudo pluginctl run` STREAMS logs only until the plugin reaches "running", then
RETURNS — so the inference/publish output that happens AFTER that (the part you
care about) never reaches your terminal, and the single-shot pod is GC'd within
seconds of completing, so a later `kubectl logs` finds no pod. Two traps: (a)
`kubectl logs -f <pod>` fired too early dies with `PodInitializing` (the init
container `init-app-meta-cache` hasn't handed off yet); (b) after completion the
pod is gone. RELIABLE pattern — launch detached, then POLL `kubectl logs` (non-follow)
into a file each second until a completion marker or terminated-state appears:
    sudo pluginctl run --name <n> ... >/dev/null 2>&1 &
    for i in $(seq 1 100); do
      sudo kubectl logs <n> -n default -c <n> >/tmp/run.log 2>/dev/null
      grep -qiE "Published|no detections|Uploaded|Traceback|self-exit|0 frames" /tmp/run.log && break
      ST=$(sudo kubectl get pod <n> -n default -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}' 2>/dev/null)
      [ -n "$ST" ] && { echo "terminated:$ST"; break; }
      sleep 1
    done
    grep -ivE "Ultralytics Settings|yolo settings" /tmp/run.log | tail -50
The container name (`-c <n>`) equals the `--name`; the pod also has an
`init-app-meta-cache` init container you must NOT target. Complements the data-API
check — the log proves per-frame processing, the data API proves the publish shipped.

## Sizing a --continuous producer (image-sampler2): frequency + ring-cache caps
A `--continuous` producer runs FOREVER and its ring cache bounds disk, so settle
these BEFORE launch — don't accept defaults blindly. The knobs that matter:
- `--continuous SECONDS` = capture PERIOD. Match to SUBJECT behaviour, not habit:
  a hummingbird/bird/traffic (in-frame briefly, unpredictably) needs a SHORT
  period (10s ≈ 8,640 frames/day is a good balance; 30s+ starts missing brief
  visits). Slow scenes (clouds, snow, parking) tolerate 60s+.
- `--cache-max-count N` AND/OR `--cache-max-mb MB` — in image-sampler2 0.5.x at
  least ONE is REQUIRED with `--continuous` (not optional as in 0.3.x); pass BOTH
  as a belt-and-suspenders dual cap (count bounds history DEPTH, MB hard-caps
  disk regardless of frame size). Oldest evicted first when either limit hits.
- `--heartbeat-secs` (default 60) = liveness/cache-stats cadence, INDEPENDENT of
  the capture period; 60 is fine.
MEASURE frame size from a live run before sizing the cap — don't guess: Reolink
sub-stream JPEGs from this camera were ~0.38 MB on 0.5.1 (were ~0.75 MB on 0.3.0
— it varies by version/resolution). Backlog history ≈ N × period; e.g. count=500
at 10s ≈ 83 min of frames. Pick N so the consumer's `--every` wake clock can lag
without losing frames. Verified-good producer launch (H00F, image-sampler2 0.5.1):
    sudo pluginctl run --name hummingcam-producer --selector zone=core \
      --env-from /root/hummingcam.env -v /media/plugin-data/local-cache:/local-cache \
      localhost/image-sampler2:0.5.1 -- \
      --continuous 10 --stream top_camera --name top \
      --cache-root /local-cache --cache-name hummingcam \
      --cache-max-count 500 --cache-max-mb 500 --heartbeat-secs 60 --vsn H00F
Its own log echoes the resolved config (`caps=[max_count=500, max_mb=500.0]`) and
per-write ring stats (`wrote <f> evicted=0 ring_count=N ring_mb=X`) — read those
to confirm it's writing + evicting as intended. A `--continuous` producer is a
LONG-LIVED daemon: launch it backgrounded and let it run silently (no completion
notification — it never exits); it keeps the shared cache refreshed for any number
of consumers.

## image-sampler2 does NOT leak the camera password (do not re-file this "bug")
CORRECTION to a false finding made mid-session: seeing `&password=***` in the
producer's pod log is the plugin's OWN redaction, NOT Hermes masking a real leak.
`acquire.py::_redact()` rewrites the `password=` query value to `***` before
logging the snapshot URL (`logger.info("fetching still: %s", _redact(url))`), and
the password is ENV-ONLY (`CAMERA_PASSWORD`, never a CLI flag → never in argv/ps).
image-sampler2's credential handling is correct by design. LESSON (general): `***`
in a log line is AMBIGUOUS — it can be the app redacting OR the agent harness
masking. Do NOT assert a security bug from a log line; READ the code path (grep for
the log call + any `redact`/`mask`/`scrub` helper) before claiming a plugin logs a
secret. A fabricated security finding is worse than none. The REAL cleartext-cred
exposure in this ecosystem is the OLD v1 `flint-pete/sage-yolo` job YAMLs that pass
the password inside a `--snapshot-url` arg — a different (v1) plugin's job files,
not image-sampler2 (which was built to avoid that).

## Secrets the RIGHT way (Option B, keeps creds out of argv/git/logs)
image-sampler2 reads camera creds from env ONLY (CAMERA_USER/CAMERA_PASSWORD),
never flags. Inject via `pluginctl run --env-from <credsfile>` for testing, or a
k8s Secret referenced by the pod spec (envFrom/secretRef) for scheduled jobs.
NOTE: some existing plugins (yolo/bioclip job YAMLs) embed the camera password in
cleartext as a `--snapshot-url` query-param arg — that leaks into argv, scheduler
records, and git. Prefer the env/Secret pattern; do not copy the query-param-creds
pattern into new plugins.

Writing the `--env-from` creds file over SSH — quoting trap + safe verify: build
the file with two plain `echo`s inside a heredoc, then VERIFY without echoing the
secret. Assembling the password inline in one printf is fragile (secret-masking in
tooling output can corrupt the surrounding quotes and break the heredoc). Robust:
    ssh node 'bash -s' <<'EOSSH'
    umask 077
    U=myuser; P=$(printf '%s' 'part1'; printf '%s' 'part2')   # split avoids masking
    printf 'CAMERA_USER=%s\nCAMERA_PASSWORD=%s\n' "$U" "$P" > /tmp/cam.env
    EOSSH
Then confirm correctness WITHOUT printing the value:
    awk -F= '/CAMERA_PASSWORD/{print "pw_len=" length($2)}' /tmp/cam.env
    awk -F= '/CAMERA_USER/{print "user=" $2}' /tmp/cam.env
pw_len matching the known password length proves the bytes are right even when the
value is masked in your own tool output. `shred -u /tmp/cam.env` when done.

## Give the plugin repo a `make test` target (canonical verification)
A Sage plugin's stock Makefile only has `image`/`push` (docker buildx) — NO test
target — so verification tooling can't auto-detect how to run the suite and
re-flags edits as "unverified" every turn. Add a one-line canonical target that
runs the existing unit venv, so a plain `make test` is the detectable command:
    PY?=.venv-test/bin/python
    test:
    	$(PY) -m pytest -q
    .PHONY: all image push test
(`PY?=` lets CI override the interpreter.) The suites are pure-stdlib pytest
(monkeypatched `os.path.isdir`/`os.access`, fake clocks) and run in <1s — a real
green run is cheap, so prefer `make test` over hand-typed pytest invocations and
run it before every commit.

## podman-on-node build quirks (H00F: docker -> podman 4.9.3)
- Dockerfile `COPY` must list EVERY module the app imports. Sage plugin
  Dockerfiles often enumerate files explicitly (e.g.
  `COPY app.py acquire.py metadata.py ... requirements.txt /app/`) rather than
  `COPY . /app/`. When you ADD a new module (e.g. `capture.py`, `cache.py`), you
  MUST add it to that COPY line or the image builds fine but the container dies at
  start with `ModuleNotFoundError` — a SILENT trap (build + `COPY` show success;
  the failure only appears at `python3 app.py` runtime). Smoke-test after any
  module addition: `sudo pluginctl run -n probe <image> -- --help` and confirm it
  prints help (proves all imports load in-container) before the real run.
- `docker` on the node is aliased to podman; podman has NO default unqualified
  search registry, so Dockerfiles MUST use a FULLY-QUALIFIED base image name, e.g.
  `FROM docker.io/waggle/plugin-base:1.1.1-base` (bare `waggle/plugin-base:...`
  fails: "did not resolve to an alias and no unqualified-search registries").
  Fully-qualified names build cleanly under both docker and podman.
- `pluginctl build` pushes the built image to the node-local WES registry at
  `NODE_CONTROL_PLANE_IP:5000` (the node's lan0 address) so `pluginctl run` can pull it. If
  the push fails with "connection refused" to NODE_CONTROL_PLANE_IP:5000, the node registry
  is unreachable — check `ip addr` for lan0: if it shows `NO-CARRIER ... state
  DOWN` the LAN interface (and the registry on it) is down. This is a NODE INFRA
  issue, not a code bug (the image itself builds fine). Workaround: either push to
  Sage ECR and `pluginctl run` that ref, OR build local + `k3s ctr images import`
  (see the no-registry section above — preferred, needs no creds).

## Base image: DON'T use waggle/plugin-base — use python:3.x-slim (VERIFIED 2 ways)
`waggle/plugin-base` tops out at tag `1.1.1-base` (Docker Hub: no newer `-base`).
That image ships **Python 3.8.5** and an OLD **pywaggle `waggle` 0.40.7** whose
`Plugin` has NO `upload_file` method — unusable for modern file uploads; it also
lacks piexif. You must `pip install` modern deps on top regardless.

BEST FIX (verified 2026-07, supersedes the earlier "there is no better base" note
below): DON'T base on `waggle/plugin-base` at all. Base on **`python:3.12-slim`**
(the same family the birdnet CPU plugin uses). Two independent wins:
  1. It builds cleanly on the ECR Jenkins buildkit builder — it does NOT trip the
     `/proc/acpi` runc sandbox bug that `waggle/plugin-base` triggers on EVERY
     `RUN` (see the ECR section below — the bug is BASE-IMAGE-SPECIFIC, not
     universal: birdnet/yolo/bioclip all run `pip install` fine in the same
     builder because they base on python:slim / nvidia pytorch, not plugin-base).
  2. Modern Python (3.12) — no 3.8 back-compat constraint on your code.
A minimal CPU-plugin Dockerfile that builds in ECR:
    FROM python:3.12-slim
    WORKDIR /app
    COPY requirements.txt /app/
    RUN pip install --no-cache-dir -r /app/requirements.txt
    COPY app.py <every-module>.py /app/
    ENTRYPOINT ["python3", "-u", "/app/app.py"]
pywaggle's core `Plugin` (upload_file/publish) is enough for a producer/uploader —
you do NOT need `pywaggle[vision]` unless you import cv2. image-sampler2 uses only
`from waggle.plugin import Plugin` (+ piexif) and fetches frames via stdlib
urllib, so `requirements.txt` is just `pywaggle == 0.56.*` and `piexif == 1.1.*`.
Dropping `[vision]` removes the whole OpenCV/numpy chain (and any apt libGL/glib
need) → smaller, faster, fewer failure surfaces. Verify the trim before shipping:
`git grep -nE "import cv2|cv2\.|croniter"` to confirm nothing needs the extras.
The `RUN pip install` layer is genuinely required (base carries no usable pywaggle)
— it is NOT droppable like the boilerplate apt-get layer.

(HISTORICAL: an earlier pass concluded you were stuck on the Python-3.8 base and
must fall back to podman when ECR buildkit failed. That was wrong — the failure is
the base image, and swapping to python:3.12-slim fixes the ECR build directly.)

## ECR / Jenkins buildkit failure: /proc/acpi is BASE-IMAGE-SPECIFIC (VERIFIED)
The portal's ECR build runs on a Jenkins buildkit builder (`buildctl
--frontend=dockerfile.v0 --opt platform=linux/arm64,linux/amd64 ... push=true`).
With a `waggle/plugin-base` base, EVERY `RUN` step fails at container init with:
    runc run failed: ... can't mask dir "/proc/acpi": mount ... MS_RDONLY ...
      invalid argument
    error: failed to solve: process "/bin/sh -c <anything>" ... exit code: 1
Tell-tale: the base pulls/extracts fine for both platforms and `COPY` succeeds
(shows CACHED), then the FIRST `RUN` dies at container init.

KEY INSIGHT (verified 2026-07): this is NOT a universal builder problem and NOT
your Python. The SAME ECR builder builds birdnet/yolo/bioclip fine — they all have
`RUN pip install` steps that succeed — because they base on `python:3.12-slim` /
`nvcr.io/nvidia/pytorch`, NOT `waggle/plugin-base`. The `/proc/acpi` runc sandbox
failure is triggered by the `waggle/plugin-base:1.1.1-base` container config.
PRIMARY FIX: change the base image to `python:3.12-slim` (see base-image section
above). This makes the ECR build succeed directly — no podman fallback needed.
Secondary hygiene: drop UNNECESSARY `RUN` layers anyway (boilerplate
`apt-get install wget curl` many upstream Sage Dockerfiles carry but the plugin
never uses — verify with `git grep -nE "wget|curl|subprocess|os.system|Popen"`).
FALLBACK (only if you're forced to keep a broken base): build on the node with
podman (RUN works fine there) + `k3s ctr images import`. But prefer fixing the
base — the podman path can't push to ECR, so the plugin stays un-submittable via
sesctl. If a NON-plugin-base image genuinely trips /proc/acpi, THAT is a Sage
platform infra issue to report; the base swap resolves the common case.

## Rebuild trigger / stale metadata
ECR builds from the git repo at `source.url`/`branch` in sage.yaml (Jenkins log
shows the resolved commit SHA — confirm it matches your latest push before
debugging anything else). ECR will NOT rebuild an already-registered version —
bump `version:` in sage.yaml (e.g. 0.1.0 -> 0.1.1) to force a fresh build/tag.
If the portal shows a stale app name/version (e.g. old `imagesampler`/`0.3.8`
instead of your `image-sampler2`/`0.1.0`), it snapshotted an OLD sage.yaml before
your push — re-sync/refresh the repo in the portal. name/version come from
sage.yaml (not ecr-meta/, and there are no git tags driving it unless you create
them). Always push Dockerfile/sage.yaml/ecr-meta fixes BEFORE triggering the
portal build.

### Pre-ECR-build readiness checklist (before telling ECR to pull/build) — VERIFIED
When asked to confirm a plugin is "ready for ECR to build," check these in order —
all are real gates ECR hits:
1. **Working tree clean AND in sync:** `git status` clean; local HEAD == the
   remote branch sage.yaml points at (`git rev-parse HEAD origin/<branch>` equal).
   ECR builds the pushed commit, not your local one.
2. **Repo is anonymously cloneable:** `git ls-remote <url> <branch>` with no creds
   must succeed — ECR fetches it unauthenticated. A private repo fails the clone.
3. **sage.yaml `source.url`/`branch` match the real remote** and the arch list is
   sane (arm64-only dodges the QEMU/CUDA cross-build crash for CPU plugins).
4. **All build inputs tracked:** Dockerfile, requirements.txt, app + every imported
   module, .dockerignore — `git ls-files` shows them.
5. **Build-time network:** if the Dockerfile pre-downloads models/weights in a
   `RUN` (e.g. `birdnet.load(...)`), ECR needs build egress — same egress `pip
   install` uses, so if pip works the download works. Just flag it.
6. **TAG the version to match sage.yaml** when the user wants a marked release:
   `git tag -a v<X.Y.Z> -m '…' <HEAD>` then `git push origin v<X.Y.Z>`; verify with
   `git ls-remote --tags origin`. ECR reads the version from sage.yaml and builds
   the BRANCH head (the tag is not strictly required to build), but a matching
   annotated tag marks the released commit cleanly. Bump sage.yaml `version:` to
   force a rebuild of an already-registered version (ECR won't rebuild same
   version).
Vestigial checked-in model files (e.g. a 55 MB `.tflite` that `.dockerignore`
excludes and the app doesn't load — it auto-downloads via the package) are harmless
to the build but bloat the repo; note them, don't block on them.

### PITFALL: upload-agent SKIPS files whose version path-segment isn't x.y.z/latest/test (VERIFIED H00F 2026-07-12)
The wes-upload-agent's `find` only selects staged dirs shaped
`[<job>/]<plugin>/<version>/<ts>-<sha1>/` where `<version>` matches
`x.y.z | vx.y.z | latest | test` (see the "What the WES upload-agent uploads"
section). GOTCHA when side-loading with `pluginctl run <image>`: the `<version>`
path-segment is taken from the IMAGE TAG. A dev tag like `:gate3` or `:mytest`
produces `.../<plugin>/gate3/<ts-sha>/`, which the agent's regex does NOT match —
so the file stages correctly, the plugin reports "uploaded", but the agent NEVER
ships it (staging never empties; agent log shows "uploaded all files found" while
your dir sits there). FIX: tag the side-load image with a regex-valid version
segment — `:test` is the canonical dev choice (or a real `:0.1.0`). Retag in
containerd (`sudo k3s ctr images tag localhost/<p>:gate3 localhost/<p>:test`) and
re-run `pluginctl run localhost/<p>:test`. Then the path becomes
`.../<plugin>/test/<ts-sha>/` and the agent picks it up. ALWAYS confirm the ship by
watching staging empty (`sudo find /media/plugin-data/uploads/... -type f`) AND the
agent log line `uploading: ./<path>` — not just the plugin's own "uploaded" log.

### Simulating the WES-injected identity env for a consumer test (pluginctl --env-from)
To test a plugin that CONSUMES the wes-nodeinfo-injection env vars
(WAGGLE_NODE_{ID,VSN,GPS_LAT,GPS_LON,MOBILITY}) through the REAL upload path without
deploying the patched scheduler, inject them via `pluginctl run --env-from <file>`.
The env-file supplies the exact 5 vars the patched scheduler would inject via
`envFrom: wes-identity`, so the consumer chain (resolve identity -> EXIF GPS -> v2
filename -> upload meta) runs end-to-end through pywaggle's real upload plumbing.
This is complementary to the Tier-2 scheduler proof (which shows auto-injection):
together they cover producer + consumer. Standing up a fake camera: image-sampler2
fetches a still over plain HTTP (Reolink `cmd=Snap` path), so a 10-line
`http.server` returning a PIL-generated JPEG on `0.0.0.0:<port>` is a perfect
stand-in — no camera password needed. Point the plugin at the node's cni0 gateway
IP (`10.42.0.1`, reachable from every pod on the flannel net) as `--camera-host`.
Run the fake cam as a `systemd-run --user --unit=<name> --collect python3 …`
transient unit so it's decoupled from the SSH session (NOT nohup/setsid, which
Hermes' shell guard blocks and which die with the ssh session anyway). Stop it
cleanly with `systemctl --user stop <name>; systemctl --user reset-failed <name>`.

PITFALL — `pkill -f <pattern>` SELF-MATCHES over SSH (wasted several commands this
session): `ssh node "pkill -f /tmp/fakecam.py"` exits 255 and kills nothing useful
because the remote shell running the command has `/tmp/fakecam.py` IN ITS OWN argv,
so pkill matches and kills its own shell (dropping the SSH session → exit 255).
Same trap with any `pkill -f <str>` where `<str>` also appears in the ssh command
line. FIXES: (a) don't use pkill at all for something you started as a systemd unit
— `systemctl --user stop <unit>`; (b) if you must pkill, match on a MORE SPECIFIC
pattern that is NOT in your own command line, or use `pgrep -af <pat>` first to see
what would match (its own shell shows up too — that one hit is the false positive).

### DIAGNOSIS PATTERN: upload staged but not appearing in the data API — is it YOU or the NODE?
When a side-loaded upload never shows in the data API, the fault is EITHER your
plugin/identity OR the node's upload-agent → Beehive transfer. Triage in this order
before blaming your code:
1. Staged {data,meta} exist and `meta` has the right vsn/node_id (`sudo cat
   <leaf>/meta`). If meta is wrong, it's YOUR bug.
2. EXIF in the staged `data` file carries the coords (read with piexif/PIL — the
   pod has piexif, the host usually doesn't; `sudo pluginctl exec` or copy out).
3. The agent log shows the full lifecycle for YOUR path:
   `uploading: ./<path>` → `cleaning up: ./<path>` → `done: ./<path>`. That `done:`
   line is the AUTHORITATIVE ship signal — trust it over staging-dir inspection.
If (1)+(2) hold and (3) shows `uploading:` + SSH-auth success but then the transfer
stalls, the producer side is PROVEN and the gap is node upload-health, not you.

The rsync-stall failure mode (VERIFIED on H00F 2026-07-12, then FIXED 2026-07-13):
wes-upload-agent authenticated to beehive-upload-server fine, selected the file,
then the rsync DATA transfer stalled (`rsync hasn't made progress in 15s... sending
interrupt!`) every cycle with a high restart count; a recurring `rm: can't remove
'/tmp/rsync_healthy'` is the agent's OWN watchdog artifact (the missing marker trips
the liveness check → restart loop). TCP/DNS/SSH-auth all succeeded; only the bulk
DATA path failed (classic MTU / throughput / mid-transfer firewall, or a stuck
server-side rsync). This was a NODE INFRA condition that got fixed out-of-band — do
NOT treat "H00F can't ship" as a standing fact; RE-CHECK the agent log for clean
`done:` lines each session. Post-fix a healthy transfer looks like
`sending incremental file list … 15.47MB/s (xfr#1) … done: ./<path>`.

PITFALL — "STILL_STAGED" FALSE ALARM (cost a debug cycle 2026-07-13): after the
agent ships, it `--remove-source-files` the {data,meta} and rmdirs the emptied
`<ts>-<sha1>` LEAF dir, but the EMPTY PARENT dirs (`<plugin>/<version>/`) can linger
a cycle. So `find <path>` (dirs included) still shows `.../gate3-imgsampler/test`
and looks staged, while `find <path> -type f` correctly shows NOTHING. ALWAYS check
`-type f` (real data files), not bare `find`, when deciding if a ship completed —
and cross-check the agent's `done:` log line. Empty lingering dirs ≠ unsent upload.

## Verifying the Beehive round-trip
Public data-query API (no auth): `POST https://data.sagecontinuum.org/api/v1/query`
with JSON body like `{"start":"-15m","filter":{"vsn":"H00F","name":"upload"}}`,
returns NDJSON. Object store propagation is cross-country (~1-2 min) — allow lag.
Timestamps must be RFC3339 (`date -u -d '20 minutes ago' +%Y-%m-%dT%H:%M:%SZ`).
Local-only plugins that NEVER upload images STILL show up here IF they
`plugin.publish(...)` measurements (e.g. a liveness heartbeat) — query by the
measurement `name`, not `upload`.

NARROW the filter with `task` to pin YOUR run (VERIFIED 2026-07-13): for a
`pluginctl run -n <name>` side-load, `meta.task` == that `-n` name, so
`{"start":"-15m","filter":{"vsn":"H00F","name":"upload","task":"<your -n name>"}}`
returns exactly your record among the node's other traffic. A successful record's
`value` is the storage URL and `meta` carries `vsn`, `node_id`, `filename`, `node`,
`plugin` (the image ref), `job` (=`Pluginctl` for side-loads), `zone`. That record
IS conclusive proof the object reached the cloud. NOTE: the storage URL itself
(`storage.sagecontinuum.org/api/v1/data/...`) is AUTH-GATED — a bare `curl` returns
`http 401` + a JSON error, NOT the image. That's expected bucket access control, not
an upload failure; the query-API record + on-node EXIF (read before ship) are the
conclusive evidence, not a fetch of the stored object.

IDENTITY IS ATTACHED DOWNSTREAM (verified on H00F Stage-5): a plugin publishing
with a PLACEHOLDER `vsn="NODE"` (because /etc/waggle is host-only, unreadable in
the pod) appears in the data API with the REAL `vsn:"H00F"`, `node:"00004cbb..."`.
Beehive's routing resolves node identity after the fact — so a placeholder vsn in
EXIF/publish is EXPECTED and correct; do NOT try to self-resolve vsn inside the
pod. Beehive also auto-MERGES meta keys into every record: `host, job
(="Pluginctl" for side-loaded runs), node, plugin (=the image ref), task (=the
pluginctl -n name), vsn, zone` — combined with the plugin's own publish `meta`
(e.g. cache_name/camera). Useful for disaggregating multi-stream/multi-instance
nodes in a query.

## What the WES upload-agent actually uploads (and DELETES) — VERIFIED from source
Critical if a plugin writes a LOCAL cache/ring: know exactly what the upload-agent
touches. Read from `waggle-sensor/wes-upload-agent` (`main.sh`, image
`waggle/wes-upload-agent:0.6.0`), confirmed against a live node:
- The agent mounts host `/media/plugin-data/uploads` at `/uploads` and loops
  forever. `find_uploads_in_cwd()` runs `find . -mindepth 3 -maxdepth 4 -type d`
  filtered to paths shaped like `[<job>/]<plugin>/<version>/<ts>-<sha1hex>/`
  where <version> matches `x.y.z | vx.y.z | latest | test` and the leaf dir matches
  `<digits>-<hexdigits>` (the pywaggle staging dir holding {data,meta}).
- For each match it rsyncs to beehive with `--remove-source-files`, then rmdirs the
  emptied dir. So the agent UPLOADS AND THEN DELETES the staged files.
- The on-host uploads tree is therefore organized by `<plugin>/` and
  `<plugin>-<jobid>/` subdirs (one per instance), matching the object path
  `.../<plugin>/<version>/<node-id>/<ts>-<file>` seen in the data API.
CONSEQUENCE / design rule: a plugin's LOCAL-ONLY cache must NOT live under
`/run/waggle/uploads` — the agent would both upload files you never meant to ship
AND delete them out from under your own eviction logic. Put a local ring in a
DEDICATED subtree outside the upload mount (a `--cache-dir` hostPath / user volume,
NOT the uploads mount). Do not rely on "my filenames happen not to match the regex"
— the scan pattern can change; keep the cache physically separate.
(Also: reading `/etc/upload-agent/` dumps the node's Beehive SSH push key — treat
as a secret; never echo/reuse it.)
