# Sage/Waggle Infrastructure — Problems to Fix & Enhancements to File

Running list of platform bugs, gaps, and enhancement requests to raise as GitHub
issues with the Sage/Waggle cyberinfrastructure team. Each entry is written to be
lifted (mostly) verbatim into an issue: it states the problem, the concrete
evidence/error signatures, the impact, a proposed fix, and the right repo/team.

SCOPE: this doc covers work OUTSIDE the plugins — pywaggle, SES/scheduler, WES,
ECR/build pipeline, Beehive/data-API, node/network, dev-env, and upstream
libraries (e.g. pybioclip). Future improvements we would code INSIDE our own
plugins (image-sampler2, bioclip, yolo, birdnet) live in the companion
`~/AI-projects/plugin-improvements.md`. Cross-cutting needs (a platform primitive
PLUS a per-plugin change) appear in both, each scoped to its side, with a
cross-ref.

Discovered during plugin development on **node H00F (Jetson Thor, arm64)** while
building `image-sampler2`, `birdnet-species`, `yolo-object-counter`, and
`bioclip-species-classifier`.

Legend: **[BUG]** platform defect · **[ENHANCEMENT]** new capability ·
**[DOCS]** documentation gap. Priority: P1 blocks work / P2 painful workaround
exists / P3 nice-to-have.

Last updated: 2026-07-08.

---

## 1. [ENHANCEMENT][P1] Plugins cannot learn their own VSN or GPS lat/lon at runtime

**Likely repos:** `waggle-sensor/pywaggle`, `waggle-sensor/waggle-edge-stack` (WES)

### Problem
There is no supported way for a running plugin to obtain the identity of the node
it is executing on — neither its **VSN** (e.g. `H00F`) nor its **GPS lat/lon**.
This forces every plugin that wants node identity or location (for filenames,
EXIF geotags, geo-filtering of ML results, etc.) to either hard-code per-node
values in the job YAML or ship a placeholder.

### Evidence (verified four independent ways, 2026-07-06)
1. **pywaggle 0.56 has no location/identity API.** `src/waggle/` has only
   `data` (audio/vision) and `plugin` (publish/subscribe/protocol). There is no
   `waggle.data.gps`, no `Plugin.get_location()`, no `Plugin.get_vsn()`. Source
   grep for `gps|latitude|longitude|location|vsn|node_name|node_id` → zero hits.
   (Writing `from waggle.data.gps import GPS` always fails — it's dead code.)
2. **pywaggle "writing-a-plugin" docs** expose only publish / subscribe /
   upload_file / timeit. Nothing about node self-identification.
3. **A live `ses`-namespace plugin pod** (`insect-bioclip`) has ONLY these
   node-relevant env vars: `WAGGLE_PLUGIN_HOST/PORT/USERNAME/PASSWORD`,
   `WAGGLE_APP_ID`, `WAGGLE_SCOREBOARD`. No VSN, no GPS. Mounts are ONLY
   `/run/waggle/uploads` and `/run/waggle/data-config.json`.
4. **The authoritative source that DOES exist — `/etc/waggle/node-manifest-v2.json`
   (fields `vsn`, `name`, `gps_lat`, `gps_lon`) plus `/etc/waggle/vsn` and
   `/etc/waggle/node-id` — is a node-HOST path and is NOT mounted into plugin
   pods.** Verified: both a bare `docker run` and a real `ses` pod report
   `/etc/waggle/` missing. Reading the manifest only works when code runs directly
   on the node host (dev/spikes), which actively MISLEADS testing — it appears to
   work on the host and then fails in the pod.

### Current platform behavior (works, but is downstream-only)
Node identity is attached **downstream by Beehive via message routing.** Confirmed
end-to-end: an `image-sampler2` upload whose FILENAME used a placeholder vsn
`NODE` came back from the data API with `meta.vsn = H00F`,
`meta.node = 00004cbb4701d16c`. So attribution is correct without the plugin
knowing — but the plugin still can't build a correct self-describing filename or
embed a real EXIF geotag, and non-Python/data-plane consumers of the bare file
have no node context.

### Impact
- Plugins that want geolocation in EXIF or accurate geo-filtering (e.g. BirdNET's
  eBird seasonal species filter) can't get coordinates → either hard-code
  `--lat/--lon` per node in the job YAML (not fleet-portable across ~100 nodes),
  or run without geo-filtering (BirdNET then matches the GLOBAL species list and
  surfaces implausible species — European warblers at a Chicago feeder).
- Filenames/metadata that want VSN must ship a placeholder or a per-node arg.

### Note
The CI/cyberinfra team indicated (2026-07-06) they will add runtime **"GPS call"**
and **"VSN call"** APIs within days. This issue documents the requirement and the
verification so the API shape can be reviewed.

### Proposed fix
- **pywaggle:** add a first-class location/identity accessor mirroring
  `waggle.data.audio.Microphone` / `.vision.Camera`, e.g.
  `Plugin.get_node_info() -> {vsn, node_id, lat, lon, alt, fix_time}` returning a
  live GPS fix on mobile nodes and manifest coords on fixed nodes.
  (See the fuller pywaggle redesign: `~/AI-projects/pywaggle2-design.md` §2, which
  also folds in the camera/RTSP metadata-preservation ladder and other
  library-domain enhancements from this list.)
- **WES:** inject node identity into every plugin pod — either as env vars
  (`WAGGLE_NODE_VSN`, `WAGGLE_NODE_ID`, `WAGGLE_NODE_GPS_LAT`,
  `WAGGLE_NODE_GPS_LON`) and/or reliably mount `node-manifest-v2.json` at a
  documented in-pod path — so non-Python plugins work without an API call.

### Interim workaround in our plugins
`image-sampler2` resolves identity with precedence
`explicit flag > runtime lookup (placeholder today) > host manifest/files`. When
unresolved: VSN → placeholder `NODE` (env `IS2_PLACEHOLDER_VSN`), lat/lon →
omitted from EXIF (NEVER fabricated). Single swap-in point marked
`TODO(sage-ci)` in `nodemeta.py::_runtime_identity()`.

---

## 2. [BUG][P1] ECR/Jenkins buildkit fails on EVERY `RUN` step (`/proc/acpi` runc error)

**Likely repo:** Sage ECR build pipeline / Jenkins buildkit infrastructure
**FILED:** https://github.com/waggle-sensor/waggle-edge-stack/issues/110 (2026-07-07)

### Problem
The portal "Register and Build" ECR pipeline cannot build any plugin whose
Dockerfile contains a `RUN` step. Every `RUN` (apt-get, pip, anything) fails at
container init.

### Evidence / error signature
```
buildctl --addr tcp://buildkitd:1234 build --frontend=dockerfile.v0 \
  --opt platform=linux/arm64,linux/amd64 ... --output type=image,...,push=true
...
#8 0.376 runc run failed: unable to start container process: error during
  container init: can't mask dir "/proc/acpi": mount src=tmpfs, dst=/proc/acpi,
  flags=MS_RDONLY, data=nr_blocks=1,nr_inodes=1: invalid argument
error: failed to solve: process "/bin/sh -c apt-get update && apt-get install ..."
  did not complete successfully: exit code: 1
```
Tell-tale that this is a BUILDER bug, not the plugin:
- The base image pulls/extracts fine for BOTH `linux/arm64` and `linux/amd64`.
- `COPY` steps succeed (show `CACHED`).
- The FIRST `RUN` dies at container init; after removing one `RUN`, the NEXT
  `RUN` fails identically — i.e. no `RUN` can execute.
- Arch-independent (both platforms hit it). Not a QEMU/emulation issue.

Root cause is a known buildkit/runc masked-paths incompatibility with the
builder host's kernel (`/proc/acpi` masking). It is on the `buildkitd` host, not
in any plugin repo.

### Root cause CONFIRMED (2026-07-07): runc CVE-2025-31133 hardening
The `/proc/acpi` masking failure is the runc masked-paths security patch set
published 2026-11-05 (CVE-2025-31133 / -52881 / -52565), which hardened how runc
masks directories (read-only `tmpfs` over `/proc/acpi`, `/proc/kcore`, etc.). The
Sage ECR `buildkitd` host was upgraded to a patched runc (>= 1.2.8 / 1.3.3 /
1.4.0-rc.3) whose stricter masked-path mount now returns `invalid argument` for
`/proc/acpi` on this builder host's kernel — so every exec/`RUN` container init
fails. This is a runc-vs-host-kernel mismatch on the builder, fixable ONLY on the
Sage side (upgrade the builder host kernel, or pin/patch runc, or relax the
buildkitd OCI masked-paths config for the build sandbox).

Why the sibling images (yolo/birdnet/bioclip) exist in ECR: they were built
BEFORE the builder's runc security upgrade. They will hit the same wall on their
next rebuild.

### Proven NOT a fix (2026-07-07, image-sampler2 v0.5.0 -> v0.5.1)
Swapping the base image does NOT help — the failure is at runc container init,
independent of base:
- v0.5.0 built on `waggle/plugin-base:1.1.1-base` -> `RUN pip3 install` failed
  with the `/proc/acpi` error.
- v0.5.1 swapped to `python:3.12-slim` (+ slimmed reqs: `pywaggle` not
  `pywaggle[vision]`, dropped unused croniter). FROM/WORKDIR/COPY all succeeded;
  `RUN pip install` failed with the IDENTICAL `/proc/acpi` error on both arm64 and
  amd64. Confirms: any `RUN` on any base fails -> builder infrastructure, full stop.
(The v0.5.1 base swap + dep slim is still a net improvement to keep — modern
Python 3.12, smaller image, no OpenCV/numpy chain — it just doesn't unblock ECR.)

### Regression proof — Sage's OWN reference plugin fails to rebuild (2026-07-07)
Registered `waggle-sensor/plugin-imagesampler` (Sage's own image sampler; the
image `waggle/plugin-imagesampler` was last published to Docker Hub ~1 year ago,
so it built cleanly on THIS pipeline before) fresh in ECR with ZERO source
changes (commit `33a4f2a`). It fails at the FIRST `RUN` — the `apt-get` step,
Dockerfile line 3 — on BOTH arm64 and amd64:
```
#9 [linux/amd64 2/4] RUN apt-get update && apt-get install -y wget curl
#0 0.266 runc run failed: unable to start container process: error during
  container init: can't mask dir "/proc/acpi": mount src=tmpfs, dst=/proc/acpi,
  flags=MS_RDONLY, data=nr_blocks=1,nr_inodes=1: invalid argument
```
Kills every "your plugin's fault" objection: Sage-owned plugin, unchanged source,
same base image that shipped their working image a year ago, dies on `apt-get`
(not pip/requirements) — literally ANY `RUN` fails at runc container init. The
only variable is the builder host. This log is attached to issue #110.

### Impact
No plugin that installs dependencies (i.e. essentially all of them —
pywaggle/piexif/torch/etc. require `RUN pip install`) can be built via the portal
ECR pipeline. Every Thor/arm64 plugin is blocked from the standard build path.

### Proposed fix
Fix the buildkit builder's runc/seccomp config so `RUN` steps can start their
sandbox (adjust masked-paths handling, or update runc/buildkit to a version
compatible with the builder host kernel). Consider adding a native arm64 build
node so Thor plugins don't cross-build under QEMU either (see issue #3).

### Interim workaround
Build natively on the node with podman (podman's `RUN` works fine), then
side-load (see issue #4 / #5). Drop any *unnecessary* `RUN` layers (many upstream
Sage Dockerfiles carry a boilerplate `apt-get install wget curl` the plugin never
uses — pywaggle plugins fetch via Python urllib), but `RUN pip install` cannot be
dropped and will still fail on the broken builder.

---

## 3. [BUG/ENHANCEMENT][P1] ECR portal cannot build arm64 NVIDIA images (QEMU crash)

**Likely repo:** Sage ECR build pipeline (Jenkins)

### Problem
Separate from issue #2: even when `RUN` steps can start, the ECR/Jenkins pipeline
runs on x86_64 and cross-builds `linux/arm64` under QEMU emulation. NVIDIA arm64
base images (e.g. `nvcr.io/nvidia/pytorch:25.08-py3`) contain aarch64 binaries
QEMU cannot emulate.

### Evidence / error signature
```
qemu: uncaught target signal 6 (Aborted) - core dumped
... build exit code 134
```
Occurs during `pip install` / `import torch` on the arm64-under-QEMU path.
Removing `linux/amd64` from `sage.yaml` does NOT help — the crash is specifically
in the arm64-under-QEMU build. (CPU-only Python images on `python:3.12-slim`
do NOT hit this — native wheels, no CUDA.)

### Impact
GPU/NVIDIA plugins targeting Thor (yolo ~5GB, bioclip ~28GB) cannot be built via
the portal. Requires the manual native-build + side-load path for every version.

### Proposed fix
Add a **native arm64 build node** to the Jenkins ECR pipeline so Thor-targeted
NVIDIA images build without QEMU. This also removes the manual per-node steps.

### Interim workaround
Native `docker build` on the Thor node + `k3s ctr images import` + ECR catalog
API registration (see issues #4, #5, and the sage-waggle skill's
`thor-arm64-deploy-pipeline.md`).

---

## 4. [BUG][P2] `registry.sagecontinuum.org` push denied for portal tokens

**Likely repo:** Sage registry / auth

### Problem
A Sage portal access token authenticates to `registry.sagecontinuum.org` (docker
login succeeds) but is read/pull-only. `docker push` is denied.

### Evidence / error signature
```
denied: requested access to the resource is denied
```
(after a successful `docker login`.) Registry writes are reserved for the Jenkins
pipeline.

### Impact
After a native Thor build (needed because of issues #2/#3), we cannot push the
image to the registry for a normal pull. Forces the `k3s ctr images import`
side-load workaround, which is per-node and manual.

### Proposed fix
Grant push/write scope to `registry.sagecontinuum.org/<namespace>/` for a
namespace-owner's portal token, so `docker push` works after a native build. This
(combined with a native arm64 builder, #3) would make the standard pull path work
on Thor.

---

## 5. [DOCS][P2] No documented, supported path for side-loading a plugin for testing

**Likely repo:** `sagecontinuum.org` docs / `waggle-edge-stack`

### Problem
The only reliable way we found to get a real Beehive round-trip during
development on Thor — build locally + import into k3s containerd + `pluginctl run`
— is undocumented. We reverse-engineered it. It should be a documented,
first-class dev workflow, because the standard ECR path is blocked on Thor
(issues #2, #3, #4).

### The working procedure (should be documented)
```bash
# Build natively on the node (podman; RUN works here, unlike Jenkins buildkit).
# Base image MUST be fully-qualified for podman:
#   FROM docker.io/waggle/plugin-base:1.1.1-base
podman build -t localhost/<plugin>:<ver> .

# Tag + import into k3s containerd (NOT the same store as podman/buildah).
podman tag localhost/<plugin>:<ver> docker.io/library/<plugin>:<ver>
podman save docker.io/library/<plugin>:<ver> | sudo k3s ctr images import -
sudo k3s crictl images | grep <plugin>          # confirm present

# Run in a real WES pod (full upload plumbing) — no ECR, no registry, no creds.
# NOTE: the per-user kubeconfig is namespace-scoped and CANNOT create pods;
# use the k3s admin kubeconfig.
sudo pluginctl run --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --name <name> --env-from <creds.env> \
  docker.io/library/<plugin>:<ver> -- <plugin args>

# Verify the round-trip (public, no auth):
curl -s -X POST https://data.sagecontinuum.org/api/v1/query \
  -H 'Content-Type: application/json' \
  -d '{"start":"-15m","filter":{"vsn":"<VSN>","name":"upload"}}'
```

### Points the docs should make explicit
- `pluginctl run` bypasses the ECR-registration gate (unlike `sesctl`/SES); it's
  the right tool for a dev round-trip. Its pods land in the `default` namespace.
- `imagePullPolicy` defaults to `IfNotPresent` for a non-`:latest` tag, so an
  image already in k3s containerd is used without a remote pull.
- **podman/buildah storage ≠ k3s containerd storage** — you must
  `podman save | k3s ctr images import`; a `podman build` image is invisible to
  k3s otherwise.
- The per-user kubeconfig may lack pod-create RBAC (`pods is forbidden: User
  "<user>" cannot create resource "pods" in namespace "default"`); document the
  admin-kubeconfig requirement, or grant a dev role.
- Inject secrets via `pluginctl run --env-from <file>` so they never appear in
  argv / process listings.
- `pluginctl build` pushes to the node-local registry at `10.31.81.1:5000`
  (the lan0 address); if lan0 is down it fails with connection-refused (see #6).
  The `k3s ctr images import` path avoids this dependency entirely.

### Base-image gotcha to document
`waggle/plugin-base` tops out at `1.1.1-base` (no newer `-base` on Docker Hub).
It ships **Python 3.8.5** and an OLD **pywaggle `waggle` 0.40.7** whose `Plugin`
has NO `upload_file` method (only get/publish/subscribe/init/stop), and no piexif.
You cannot "get a newer base image"; you MUST `pip install pywaggle[vision]==0.56.*`
(and any other deps) on top, and keep code Python-3.8-compatible.

---

## 6. [BUG][P2] H00F `lan0` down → node-local registry (`10.31.81.1:5000`) unreachable

**Likely scope:** node H00F hardware/network

### Problem
`pluginctl build` pushes the built image to the node-local WES registry at
`10.31.81.1:5000` so `pluginctl run` can pull it. On H00F this push fails.

### Evidence
```
pinging container registry 10.31.81.1:5000: Get "https://10.31.81.1:5000/v2/":
  dial tcp 10.31.81.1:5000: connect: connection refused
```
`ip addr` shows `lan0` (the `10.31.81.1/24` interface) as
`<NO-CARRIER,BROADCAST,MULTICAST,UP> ... state DOWN` — the LAN interface is down,
so the registry hosted on it is unreachable. (The image itself builds fine; this
is node infra, not code.)

### Impact
The `pluginctl build`→node-registry→`pluginctl run` path is broken on H00F.
Worked around via `k3s ctr images import` (issue #5), which doesn't need the
registry.

### Proposed fix / question for the team
Is `lan0` being down on H00F expected? If not, bring the interface (and the
node-local registry) back up. Note the same `10.31.81.1` VIP is used for the
control-plane API on :6443 (see issue #7) — worth checking whether these are
related.

---

## 7. [BUG][P2] Node control-plane link goes stale after reboot ("plugins stopped reporting")

**Likely repo:** `waggle-edge-stack` / k3s node provisioning

### Problem
After a node reboot, k3s can be `active` and WireGuard healthy, yet the node
never re-converges its connection to the k3s control-plane API server, so SES
cannot (re)launch plugin pods and ALL of the node's plugins go dark
simultaneously. Presents as "a plugin stopped reporting" but is node-level.

### Evidence / signature
- Data API: heartbeat AND detection topics for ALL of the node's plugins stop at
  the SAME instant (a single plugin bug can't do that).
- `uptime` shows the node rebooted right at that instant.
- Definitive test on the node:
  `sudo kubectl get pods -n ses --request-timeout=30s` →
  `dial tcp 10.31.81.1:6443: i/o timeout` (or `http2: client connection lost`).
- Journal: `http2: client connection lost` degrading to
  `dial tcp 10.31.81.1:6443: i/o timeout`, failed node-lease updates, pods unable
  to fetch service-account tokens from `:6443`. Route to the VIP exists and
  WireGuard has a recent handshake — the link was up pre-reboot and never
  re-converged.

### Impact
Silent multi-day outages of all plugins on a node until someone restarts k3s.

### Interim recovery
`sudo systemctl restart k3s` on the node usually re-establishes the control-plane
link; then verify pods repopulate and the heartbeat resumes in the data API.

### Proposed fix
Make the node's control-plane reconnect robust across reboots (auto-restart k3s
on stale-lease/TLS/token failure, or a watchdog that detects `:6443`
unreachability and restarts). Investigate whether a stale TLS cert / node-lease /
token is the trigger.

---

## 8. [DOCS][P3] Data-API records key the job NAME under `meta.task`, not `meta.job`

**Likely repo:** `sagecontinuum.org` docs / data API

### Problem
When verifying a deployment via the data-query API, filtering/grouping results on
`meta["job"]` yields `job="?"` and ZERO matches — which looks exactly like "the
deploy is broken / nothing is publishing" when the job is actually healthy. There
is no `meta.job` key on these records.

### Correct usage
- The job NAME is in `meta["task"]` (e.g. `"insect-bioclip"`).
- The plugin VERSION is the tail of `meta["plugin"]`
  (`registry.sagecontinuum.org/<ns>/<name>:<VERSION>`).
- Other meta keys present: `camera`, `host`, `node`, `vsn`, `zone`, `rank`.

### Proposed fix
Document the record `meta` schema (which keys exist, what each means) on the data
API page, and explicitly note there is no `meta.job`. This trap has cost repeated
false "the plugin is dead" diagnoses.

---

## 9. [DOCS/ENHANCEMENT][P2] `pluginSpec` volume mounts: field EXISTS but is gated, insecure-by-TODO, and undocumented

**Likely repo:** `waggle-edge-stack` / `edge-scheduler` (SES job schema) / docs

**CORRECTED 2026-07-08** (was: "schema doesn't expose volume/hostPath mounts").
Source review of `edge-scheduler` shows the field DOES exist — the original
framing was wrong. See `~/AI-projects/local-cache-design.md` §6.

### What's actually true (verified from source)
`datatype.PluginSpec` has `Volume map[string]string` (plugin.go:44), and SES
mounts each `from→to` entry as a hostPath into the plugin pod
(resourcemanager.go ~L776, `hostPathDirectoryOrCreate`). So a job CAN already
request a hostPath mount (e.g. `/media/plugin-data/local-cache → /local-cache`, or
in principle the node manifest for issue #1). The problem is not absence of the
field; it's that the field is:
1. **Gated on a nodeSelector** — mounting errors out without `--selector`/`--node`
   (resourcemanager.go ~L807: "volume mounting requires nodeSelector"). Fine for
   pinned deployments, awkward for fleet-portable jobs.
2. **Insecure by an unresolved TODO** — a commented-out `IsOwnedByRoot` check
   (resourcemanager.go ~L777) was meant to forbid mounting non-root-owned host
   dirs; until it's resolved, arbitrary hostPath mounting is a flagged security
   concern (a plugin could mount system dirs).
3. **Undocumented** — no job YAML in our repos uses it; it's absent from the docs,
   so authors don't know it exists.

### Impact
Couples issue #1 and the `/local-cache` work (Blocker 1 / #4.2): the mount
mechanism exists but isn't a safe, documented, fleet-portable path. For node
identity (#1), a direct env/API injection is still preferable to mounting the
manifest. For `/local-cache`, the clean interface is WES owning the path (see fix).

### Proposed fix
- **Document** the `volume:` field and its nodeSelector requirement.
- **Resolve the root-ownership security TODO** (initContainer ownership check, or
  an allowlist of safe host paths) so hostPath mounting can be safely enabled.
- **Preferred for `/local-cache`:** rather than each job hand-rolling a raw
  hostPath, add a `sage.yaml` opt-in (e.g. `local_cache: true`) that makes SES
  auto-mount the WES-owned `/local-cache` path — sidesteps the root-owner concern
  and the nodeSelector friction. (See `local-cache-design.md` §4/§6.)
- For issue #1 specifically, direct identity injection (env/API) still beats
  mounting the manifest.

---

## 10. [ENHANCEMENT][P3] Credentials-in-argv pattern in existing plugin job YAMLs

**Likely repo:** our plugin repos (`sage-yolo`, `sage-bioclip`) — but a platform
pattern worth a convention

### Problem
The existing yolo/bioclip job YAMLs embed the camera password in cleartext as a
`--snapshot-url` query-param arg, e.g.
`--snapshot-url "http://.../api.cgi?...&user=CAMERA_USER&password=CAMERA_PASSWORD&..."`.
This leaks the credential into: the pod's argv (visible via `kubectl describe
pod` / process listing), the SES/scheduler job record, and git history.

### Proposed fix / convention
Adopt an env/Secret pattern platform-wide: plugins read camera creds from
`CAMERA_USER` / `CAMERA_PASSWORD` (env only, never args), injected via a k8s
Secret referenced by the pod spec (`envFrom`/`secretRef`) for scheduled jobs, or
`pluginctl run --env-from <file>` for testing. `image-sampler2` already does this.
Follow-up cleanup: rotate the leaked password and migrate the yolo/bioclip jobs.
(Also: document whether SES `pluginSpec` supports `envFrom`/`secretRef` — needed
for the scheduled-job version of this pattern.)

---

## 11. [ENHANCEMENT][P3] BirdNET geo-filtering silently disabled without coordinates

**Likely repo:** downstream of issue #1; also a docs note

### Problem
`birdnet.load("geo","2.4","tf").predict(lat, lon, week=...)` builds the species
set used to filter acoustic predictions. Without coordinates the geo model is
skipped and predictions match the GLOBAL species list, surfacing implausible
species (European warblers / nightingale / magpie at a Chicago feeder). The
plugin logs `No node manifest found — geo-filtering disabled`.

### Root cause
Same as issue #1 — the plugin can't get lat/lon at runtime inside the pod.

### Proposed fix
Resolved by issue #1 (runtime GPS call). Until then, pass `--lat/--lon` explicitly
in the BirdNET job YAML (values from the host manifest) to re-enable geo-filtering
and allow safely lowering the detection threshold.

---

## 12. [BUG][P2] `pluginctl run` ignores the kubeconfig context namespace (hardcodes `default`)

**Likely repo:** `waggle-edge-stack` / `edge-scheduler` (`pkg/pluginctl`)

**Found during:** image-sampler2 Stage-4 on-node verification on H00F (2026-07-06).

### Problem
`pluginctl run/ps` targets the `default` namespace regardless of the current
kubeconfig context's `namespace:` field. A node user (`beckman`) whose
`~/.kube/config` sets `current-context: default` with `context.namespace: beckman`
still gets:
```
Error: pods is forbidden: User "beckman" cannot create resource "pods"
in API group "" in the namespace "default"
```
`beckman` CAN create pods in `beckman` (`kubectl auth can-i create pods -n beckman`
= yes), and the context namespace IS `beckman`, but pluginctl uses `default`
anyway. The binary exposes `DefaultNamespace`/`SetNamespace` symbols, suggesting a
hardcoded default rather than client-go's `NamespaceParam` context resolution.

### Evidence
- `kubectl --kubeconfig ~/.kube/config config view --minify` shows
  `context.namespace: beckman`, `current-context: default`.
- `pluginctl ps` → `cannot list ... in the namespace "default"`.
- `sudo pluginctl ...` works because root's kubeconfig
  (`/etc/rancher/k3s/k3s.yaml`) is cluster-admin and can touch `default`.

### Impact
Non-admin namespace-scoped users can't use `pluginctl` without `sudo`
(cluster-admin), defeating per-user namespace isolation. Forces everyone to run
plugin tests as cluster-admin.

### Workaround
Run `sudo pluginctl ...` (uses the root cluster-admin kubeconfig).

### Proposed fix
Have pluginctl resolve the namespace via client-go's standard precedence
(`--namespace` flag → `$POD_NAMESPACE`/env → kubeconfig context namespace →
`default`), and add an explicit `--namespace/-N` flag. Neither `POD_NAMESPACE`
nor the context namespace is honored today.

---

## 13. [BUG/DOCS][P3] `pluginctl run --node <hostname>` fails scheduling with volume mounts; `--selector <label>` works

**Likely repo:** `edge-scheduler` (`pkg/pluginctl`) + docs

**Found during:** image-sampler2 Stage-4 on-node verification on H00F (2026-07-06).

### Problem
When mounting a host volume (`-v hostpath:podpath`), pluginctl requires a node
selector ("volume mounting requires nodeSelector. Please specify the node by
--selector or --node"). Passing `--node <kubernetes.io/hostname>` (the exact node
name, e.g. `00004cbb4701d16c.agx-thor`) produces a pod that never schedules:
```
Warning FailedScheduling ... 0/1 nodes are available:
1 node(s) didn't match Pod's node affinity/selector.
```
The same run with `--selector zone=core` (a node label) schedules immediately and
runs. So `--node <name>` builds a node-affinity that doesn't match the node, while
`--selector <label>` works.

### Evidence
- Node labels include `kubernetes.io/hostname=00004cbb4701d16c.agx-thor` and
  `zone=core`.
- `--node 00004cbb4701d16c.agx-thor -v ...` → `FailedScheduling` (affinity
  mismatch), pod stuck `Pending`.
- `--selector zone=core -v ...` → `Running` in ~8s.

### Impact
The documented `--node` path for pinning a mounted-volume plugin to a specific
node silently fails to schedule; users must know a matching node label instead.
Minor, but wasted ~a cycle to diagnose.

### Proposed fix
Fix `--node` to build affinity on `kubernetes.io/hostname` (or accept the label
the node actually carries), and/or document that `--selector <label>` is the
reliable way to pin a volume-mounted plugin. Clarify the exact expected `--node`
value format in the pluginctl README.

---

## 14. [ENHANCEMENT][P2] ECR catalog registration as a documented first-class API (decoupled from build)

**Likely repo:** `waggle-sensor` ECR (`ecr.sagecontinuum.org`) / SES

### Problem
SES validates a job's image against the ECR **app catalog** — not the Docker
registry and not the image present on the node. If the catalog has no record for
the exact version, `sesctl submit` fails with `... does not exist in ECR`, even
when the image is sideloaded and runnable. The only blessed way to create that
record is the portal "Create App / add version" UI, which is welded to the
(broken-for-Thor) build step (#2, #3).

### What we discovered
Catalog registration CAN be done directly via the API:
`POST https://ecr.sagecontinuum.org/api/submit` with header
`Authorization: Sage <portal-token>` + full app metadata JSON (clone an existing
version via `GET /api/apps/<ns>/<name>/<ver>`, bump version + git source, re-POST;
`description` required). This cleanly separates "register metadata" from "build
image."

### Impact / fix
Decoupling unblocks the sideload path (#5) and any "image built elsewhere"
scenario. Officially support + document a "register a version" API (and/or a
`sesctl` subcommand), and make `imagePullPolicy=IfNotPresent` + catalog-only
registration a SUPPORTED deployment mode, not an accident.

---

## 15. [ENHANCEMENT][P2] Scheduler GPU time-sharing / bounded-runtime primitive

**Likely repo:** `waggle-edge-stack` (SES / edge-scheduler)

### Problem
A single-GPU node cannot run two always-on continuous GPU plugins — a held GPU
blocks the second pod from scheduling at all. SES has no native "run this plugin
for N minutes, then yield the GPU" concept.

### Current workaround (pushed into plugin code — see plugin-improvements XP-1)
Each plugin adds `--max-runtime N` to self-exit after N seconds (image-sampler2
Stage 3.3 already does), then operators stagger plugins with cron guard-bands
(e.g. YOLO :00-:10, BioCLIP :20-:30) to share one GPU at ~20 min/hour. This works
but pushes scheduling policy into every plugin, and the timer is wall-clock
(model load eats the window).

### Proposed fix
A scheduler-level **GPU lease / time-window** primitive: declare a plugin holds
the GPU for a bounded window on a cadence; SES enforces start/stop + mutual
exclusion (with guard-bands) across plugins contending for `resource.gpu`.
And/or a node-level **GPU mutex** so two GPU plugins co-schedule safely with SES
serializing access. Would let us retire the per-plugin timers.

---

## 16. [ENHANCEMENT][P2] Versioned provenance / data-quality annotation stream

**Likely repo:** Beehive / data-API / `sage_data_client`

### Problem
When a plugin bug is found + fixed (e.g. the birdnet geo-filter bug — records
before 0.1.4 contain unfiltered global species), there's no standard way to
annotate the archive: "data in this window, from this plugin version, has caveat
X." We keep historical data rather than deleting it, so consumers need a
machine-readable trust signal. Today every record carries `meta.plugin`
(`registry.../<name>:<ver>`) as a join key, but there's nowhere to attach the
MEANING (which versions are known-bad, why, over what time range).

### Proposed fix
A standard **annotation / data-quality stream** (e.g. `env.annotation.*`) carrying
`{start_ts, end_ts, node, plugin, version, severity, note}` markers clients can
join against; and/or a sidecar provenance record per job/version + a documented
`sage_data_client` query pattern for "only records from plugin versions >= X" /
"flag records overlapping a known-issue window."

---

## 17. [DOCS][P2] `sesctl` reference docs don't match the binary

**Likely repo:** `waggle-sensor` docs site / edge-scheduler README

### Problem
Published `sesctl` docs diverge from the actual binary:
- Docs imply `sesctl create --from-file`; binary uses `-f` / `--file-path`.
- Docs imply submit/manage BY JOB NAME; binary requires `submit -j <numeric-id>`
  (the numeric ID returned by `create`). Suspend = `rm -s <id>`, remove = `rm <id>`.

### Impact / fix
Every new author follows the docs and hits immediate confusing failures. Correct
the reference docs + edge-scheduler README to the real flags and the
create-returns-numeric-id -> submit-by-id workflow. (Our internal skill is already
patched; an upstream issue/PR is warranted.)

---

## 18. [NOT-A-BUG / RESOLVED] NRP storage: slow caching (minutes) + rate-limited probes — NOT permanent loss

**Likely repo:** Beehive / NRP storage replication (`nrdstor.nationalresearchplatform.org`)

**First observed:** 2026-06-18 (~04:55 UTC). **RE-VERIFIED RESOLVED: 2026-07-08.**

### Resolution (2026-07-08 re-verification on H00F)
Re-tested against live `bioclip-species-classifier` image uploads on H00F. Files
DO land in NRP object storage — this is NOT the permanent-loss outage originally
feared. Definitive census: **12 of 12 files older than 5 minutes were retrievable
(HTTP 200 real JPEG bytes), 0% permanently missing.** The redirect chain works as
designed: `storage.sagecontinuum.org` → HTTP 302 →
`nrdstor.nationalresearchplatform.org:8443` → object.

What actually happens (two normal behaviors, mistaken for a bug):
1. **Propagation/caching lag (a handful of minutes).** A freshly-uploaded object
   can return HTTP 404 for the first ~2–5 minutes before it replicates/caches to
   NRP, then serves 200. Watched multiple files go 404 → 200 as they aged
   (e.g. the 00:20:56 and 00:21:13 objects were 404 while <5 min old, then 200
   once older). This is replication latency, categorically different from the
   permanent 404s of the 2026-06-18 event. **Consumers must tolerate a few
   minutes' delay before a just-uploaded file is fetchable.**
2. **Rate-limited downloads/probes.** Hammering the NRP host with rapid
   back-to-back requests (tight loops) trips a connection cap and returns
   connection failures/timeouts (curl `000`) — NOT 404s, and NOT missing files.
   Well-spaced requests (≥~2–4 s apart) return 200 reliably. **Batch verification
   / bulk downloads must throttle and space their requests.**

### Verification method (for next time)
- Pull the upload record's `value` URL straight from the data API JSON (do NOT
  string-split filenames — a stray split turns the capture-ts prefix into a bogus
  hostname and yields false `Could not resolve host` / `000` errors).
- Only judge a file "missing" once it is **>5 minutes old** (older than the
  caching lag). Space probes several seconds apart to avoid the rate-limit `000`.
- `curl -s -o /dev/null -w "%{http_code}" -L -u beckman:$TOKEN "$URL"` per file.

### Original 2026-06-18 symptom (retained as history)
`plugin.upload_file()` produced a data-API record with a valid storage URL, but
the file returned HTTP 404 from NRP with `Unable to open /sage/node-data/...; no
such file or directory`, across multiple plugins/nodes (sage-yolo H00F, bioclip
H00F, wxt536 W08D). Text/numeric measurements were unaffected; only FILE uploads.
That acute event appears to have cleared; current behavior is only the lag +
rate-limit above.

### Residual note (P3, optional)
If desired, ask the Beehive/NRP team to (a) document the expected
upload→retrievable caching delay so consumers don't treat a fresh 404 as loss,
and (b) confirm the download rate-limit thresholds. Neither blocks work; the
storage path is functional.

---

## 19. [BUG][P2] pybioclip (upstream) does not support BioCLIP 2.5

**Likely repo:** `Imageomics/pybioclip` (UPSTREAM library, not Sage) — maintainers
egrace479, jbradley

### Problem
`pybioclip` 2.1.5 raises `ValueError: TreeOfLife predictions are only supported
for ... bioclip, bioclip-2` when passed `bioclip-2.5-vith14`. Two gaps:
`_constants.py::TOL_MODELS` lacks the 2.5 entry; `predict.py` hardcodes
`txt_emb_species.{npy,json}` while 2.5 uses model-specific filenames
(`txt_emb_bioclip-2.5-vith14.{npy,json}`, present in the TreeOfLife-200M repo).

### Impact / fix
Blocks using BioCLIP 2.5 via the stock library. Our plugin-side workaround is
`patch_pybioclip.py` (see plugin-improvements BC-1). Upstream fix is ~15 lines:
add 2.5 to `TOL_MODELS` + make the embedding-filename lookup model-aware. When
merged, our plugin drops the patch. (Cross-ref: plugin-improvements BC-1.)

---

## 20. [ENHANCEMENT][P2] Per-model resource declaration + clear OOM failure

**Likely repo:** `waggle-edge-stack` (pluginctl / SES) / ECR portal

### Problem
BioCLIP 2.5 Huge (ViT-H/14) OOMKills at `memory=8Gi,limit.memory=16Gi` (weights
~4-5GB + 3GB text embeddings + PyTorch overhead > 16Gi); needs
`memory=16Gi,limit.memory=32Gi`. The failure is an opaque `OOMKilled`, not a
clear "insufficient resources" message.

### Impact / fix
pluginctl/ECR should document per-model resource requirements, or let a plugin
declare MINIMUM resources in sage.yaml so under-provisioned deployments fail with
a clear message rather than an opaque OOMKill. (Plugin-side: bake correct requests
into each plugin's sage.yaml — plugin-improvements BC-2.)

---

## 21. [BUG][P3] SSH agent key loss on long operations via `sage-vpn`

**Likely scope:** dev-env / `sage-vpn` proxy + local SSH config

### Problem
SSH to `*.sage` via the `sage-vpn` ProxyJump fails with
`Permission denied (publickey,password)` after extended operations (5-15 min:
docker builds, k3s imports, polling). The `*.sage` host block relied on the SSH
agent for the key; when the agent key expired or the control-master timed out,
proxied connections couldn't authenticate.

### Mitigation (applied) / fix
Add explicit `IdentityFile ~/.ssh/sage_key` + `IdentitiesOnly yes` to the
`*.sage` block (helps but agent key still expires periodically -> manual
`ssh-add`). Launch long ops via `nohup`/background so they survive disconnects.
Root cause (agent/control-master lifetime under the proxy) still unclear —
document the required SSH config for node access.

---

## 22. [DOCS][P3] Assorted platform documentation gaps

**Likely repo:** `waggle-sensor` docs / pywaggle examples

Small, high-friction-reduction doc fixes surfaced repeatedly:
- **Negative-safe sentinels in shared templates/examples.** Any Sage/pywaggle
  example gating on coordinates/temperatures must use explicit `== sentinel` (not
  `value > -1`) — real data is legitimately negative. (Caused the birdnet geo-filter
  bug; plugin-side audit in plugin-improvements XP-3.)
- **Document `imagePullPolicy` semantics.** Sideloaded images being honored
  (IfNotPresent) is the linchpin of the Thor workaround (#5) but is undocumented.
- **"Connecting to common cameras/sensors" cookbook.** Auth quirks differ wildly
  (Reolink query-param auth NOT basic; Mobotix M16 MxPEG basic auth; Hanwha
  SUNAPI snapshot needs an MJPEG profile). Save every author the rediscovery.
- **Model-load vs window-budget guidance.** Where bounded runtimes exist (#15),
  document that a ~28GB model load eats minutes of a wall-clock window.

---

## Cross-cutting: the durable fix

Issues #2, #3, #4, #5, #6 all stem from the same root: **there is no working
first-class build/deploy path for arm64 Thor plugins.** The highest-leverage fixes:
1. Add a **native arm64 build node** to the Jenkins ECR pipeline (fixes #3, and
   removes the QEMU class of failures).
2. Fix the **buildkit `/proc/acpi` runc bug** on the builder (fixes #2).
3. Grant **registry push scope** to namespace-owner tokens (fixes #4; enables a
   normal pull path after native build as a bridge).
Together these would let the standard portal "Register and Build" → pull path
work on Thor and retire the manual side-load workaround (#5).

For plugin-side identity/geo (#1, #9, #11), the highest-leverage fix is a
**pywaggle runtime node-info accessor + WES injecting node identity into every
pod's env** — the CI team's planned GPS/VSN runtime calls.
