# /local-cache — Shared Node Cache Design (DRAFT / discussion)

Status: DRAFT for discussion. A proposal for a **shared, node-persistent,
cross-plugin cache** on Sage/Waggle nodes — the missing piece that makes the
producer/consumer plugin pattern (one plugin fills a ring, another reads it)
actually work in production. Written to be lifted into upstream design/RFC issues
for `waggle-sensor/waggle-edge-stack` (the infra half) and
`waggle-sensor/pywaggle` (the library half).

Author: Pete Beckman <pete.beckman@northwestern.edu>
Companions:
- `~/AI-projects/pywaggle2-design.md` — the pywaggle2 library redesign (this doc's
  Layer-1 cache primitive is the cache slice of that library).
- `~/AI-projects/Infra-problems-to-fix.md` — #9 (pluginSpec volume mounts), #4.2 /
  Blocker-1 (no shared cache mount), #15 (GPU time-share).
- `~/AI-projects/image-sampler2/readiness-gap.txt` — Blocker 1 (producer with no
  way to consume) is the motivating symptom.
- `~/AI-projects/image-sampler2/cache.py` — the WORKING reference ring
  implementation (count/MB eviction) that becomes the Layer-1 primitive.

---

## 0. One-paragraph thesis

image-sampler2 proved the producer/consumer plugin pattern end-to-end, but it
CANNOT function on a real node: its cache root resolves `$IS2_CACHE_ROOT →
/local-cache → /tmp`, and on a node `/local-cache` doesn't exist, so it lands on
`/tmp` — which is pod-ephemeral and pod-private, invisible to any consumer. The
producer writes into a black hole. The fix is a **shared, node-persistent cache
directory** mounted into multiple pods, governed by a **two-layer eviction model**:
plugins own graceful, semantics-aware eviction (Layer 1, in the library); a WES
node service owns a blunt, semantics-free hard-quota backstop (Layer 2, a managing
pod) so one runaway plugin can't fill the disk and starve its neighbors. Crucially,
the exact architecture already exists on the node for `/uploads` — a shared
hostPath drained by a privileged DaemonSet — so this is a well-trodden pattern,
not a new invention.

---

## 1. The problem, concretely (verified from source, 2026-07-08)

### 1.1 Why /tmp fails
- image-sampler2 `cache.py` resolves cache root `$IS2_CACHE_ROOT → /local-cache →
  /tmp`. `/local-cache` is not mounted on any node, so production lands on `/tmp`.
- A plugin pod's `/tmp` is the container's own writable layer (or an emptyDir):
  **pod-ephemeral** (vanishes on pod exit) AND **pod-private** (no other pod can
  see it). A consumer pod literally cannot read the producer's frames.
- Net: we PRODUCE but nothing can CONSUME. The architecture is inert in production.

### 1.2 What the node ALREADY does for /uploads (the template)
Read from `edge-scheduler` (`pkg/nodescheduler/resourcemanager.go`) and
`waggle-edge-stack` (`kubernetes/wes-upload-agent.yaml`):

- Each plugin pod gets a hostPath volume:
  `hostPath: /media/plugin-data/uploads/<job>/<plugin>/<tag>` mounted at
  `/run/waggle/uploads` (resourcemanager.go ~L682). This is REAL persistent disk
  under `/media/plugin-data/`, not tmpfs.
- The `wes-upload-agent` **DaemonSet** mounts the PARENT tree
  `hostPath: /media/plugin-data/uploads` at `/uploads` and drains every plugin's
  subdir upstream (upload-agent.yaml L55-58).
- So `/uploads` is already a **per-plugin subdirectory under a shared host tree,
  serviced by a privileged node-level DaemonSet.** That is exactly the shape
  `/local-cache` needs. We are copying a proven pattern.

The ONLY structural difference: the upload-agent's lifecycle rule is "drain
upstream, then delete." A cache is **never uploaded** — its lifecycle rule is
"evict by size/age." Same shape, different reaping predicate. That predicate
difference is the entire reason Layer 2 is a NEW service and not the upload-agent.

### 1.3 No storage quota exists today (verified)
- SES maps only `limit.cpu`, `limit.memory`, `limit.gpu`, `request.cpu`,
  `request.memory` from `sage.yaml`'s `resource:` block
  (resourcemanager.go `resourceListForConfig`, plugin.go `PluginSpec`). There is
  **no ephemeral-storage handling**. (Unknown resource names fall through a
  `default:` branch as raw limits, so `limit.ephemeral-storage` COULD be passed,
  but nothing does and it's undocumented/accidental.)
- The cluster LimitRange (`wes-default-limits.yaml`) sets only default **memory**
  (1Gi limit / 300Mi request / 500m cpu). No ephemeral-storage default, no
  `ResourceQuota` anywhere.
- The only storage backstop today is **kubelet node `nodefs` disk-pressure
  eviction** (generic k8s). Evidence they lean on it: the upload-agent carries a
  `node.kubernetes.io/disk-pressure` toleration so it keeps draining under
  pressure. This protects the NODE, not a well-behaved neighbor, and evicts whole
  pods bluntly.

### 1.4 The hostPath accounting trap (the key constraint)
Even if a per-pod `ephemeral-storage` limit WERE set, it would NOT bound
`/local-cache`: kubelet's ephemeral-storage accounting does **not** count hostPath
volumes. emptyDir `sizeLimit` is likewise irrelevant to a hostPath. So the shared,
persistent properties we NEED are exactly the properties that make the cache
escape every k8s-native storage guard. **A purpose-built quota (Layer 2) is the
only thing that can bound `/local-cache`.** This is not optional hardening; it is
the sole mechanism.

---

## 2. Design principle: two layers, different owners

Eviction has two genuinely different concerns that must not be conflated:

| | Layer 1 — POLICY | Layer 2 — QUOTA |
|---|---|---|
| Question | What to keep / drop, in what order | Don't let anyone eat the disk |
| Nature | Semantic, data-aware | Blunt, semantics-free |
| Examples | keep N images; keep M MB; LRU DB rows; keep-last-per-camera | hard byte ceiling per plugin subdir + per node |
| Fires | continuously, as the plugin writes | only when a plugin EXCEEDS its cap (misbehavior) |
| Owner | the PLUGIN (via pywaggle2 cache primitive) | a WES node service (managing pod) |
| Repo | `pywaggle` (+ each plugin's config) | `waggle-edge-stack` |

Rationale (the crux): only the plugin knows its data's meaning, so only the plugin
can evict gracefully — image-sampler2 keeps newest-N frames; someone else's plugin
might keep an LRU SQLite DB; a third keeps last-frame-per-camera. WES cannot own a
plugin-global policy without understanding every plugin's data. BUT WES must own a
hard ceiling that does NOT depend on the plugin behaving, or one buggy plugin fills
the disk and takes down its neighbors (and, via disk-pressure, the node). The two
coexist: graceful ring in the plugin, hard wall in the platform, wall fires only on
misbehavior.

---

## 3. Layer 1 — plugin-side graceful eviction (pywaggle2 cache primitive)

### 3.1 What it is
Hoist image-sampler2's proven `cache.py` ring into a pywaggle2 CORE primitive
(pure-Python, no cv2 — mirrors how `upload_file()` is core), so every plugin gets
a shared-cache read/write/evict API the way it gets `upload_file()`:

```python
# producer
p.cache_file(path_or_bytes, name=..., timestamp=capture_ts,
             keep_max_count=500, keep_max_mb=2048)   # graceful ring, plugin-owned
# consumer
p.read_cache(name=..., select="newest")              # or closest-before/after ts
```

### 3.2 Responsibilities (Layer 1 owns)
- **Path resolution:** `$WAGGLE_LOCAL_CACHE → /local-cache → /tmp` (the `/tmp`
  fallback stays ONLY for local dev; on a node the mount exists). image-sampler2
  already does exactly this shape.
- **Filename layout:** capture-ts-prefixed, sha1-keyed (same as uploads) so
  selection by time works and names don't collide across plugins.
- **Graceful eviction:** the plugin's own strategy — count/MB today (cache.py),
  extensible to LRU/per-camera. Runs on every write. This is what keeps a
  well-behaved plugin FAR under its Layer-2 cap.
- **Cross-user reads (design 4.2 / IS-7):** write files world-readable + dirs
  traversable (chmod-on-write) so a consumer pod running as a DIFFERENT uid can
  read the producer's files. Needs an on-node probe once a real mount exists.
- **Optional cache announcement (IS-5):** publish a Waggle record / write a
  `manifest.json` so consumers discover the cache by more than convention.

### 3.3 What Layer 1 does NOT do
It does not and cannot enforce a hard ceiling that survives its own bugs — a
plugin whose eviction logic breaks (or that never evicts) needs to be caught from
OUTSIDE. That is Layer 2.

---

## 4. Layer 2 — WES hard-quota backstop (a managing pod)

### 4.1 Yes, it's its own pod — modeled on wes-upload-agent
WES services are each their own pod (verified: 44 `wes-*.yaml`; upload-agent is a
DaemonSet, gps-server a Deployment, etc.). The cache manager follows suit:

**New `wes-local-cache-manager` DaemonSet** (`waggle-edge-stack/kubernetes/
wes-local-cache-manager.yaml`), modeled almost line-for-line on
`wes-upload-agent.yaml`:
- Mounts the shared cache ROOT `hostPath: /media/plugin-data/local-cache` →
  `/local-cache` (parent of all plugin subdirs), exactly as upload-agent mounts
  the uploads parent.
- `priorityClassName: system-node-critical` + `node.kubernetes.io/disk-pressure`
  toleration, so it keeps reclaiming under disk pressure (same as upload-agent).
- Tiny resource footprint (upload-agent is 25Mi memory / 250m cpu).
- A small manager image `waggle/wes-local-cache-manager`.

### 4.2 What the manager does (Layer 2 logic)
On a periodic sweep (e.g. every 60s) it walks each
`/local-cache/<namespace>/<plugin>/` subdir and enforces:
- a **per-subdir hard byte cap** (isolation: one plugin can't evict another's
  data), and
- a **per-node total cap** (the outer bound on all caches combined).

When a cap is exceeded, delete **oldest-first** (by capture-ts filename prefix)
until back under. It is deliberately **semantics-free**: it may throw away data the
plugin considered important — acceptable precisely because it only fires on a
plugin that has ALREADY blown past its allocation (i.e. is misbehaving). A
well-behaved plugin's Layer-1 ring keeps it far below the cap, so Layer 2 never
touches it.

### 4.3 Quota granularity (decision: per-plugin-instance subdir)
Cap per `<namespace>/<plugin>/` subdir (mirrors how `/uploads` is already keyed
`<job>/<plugin>/<tag>`), with a per-node total as the outer bound. This gives
isolation — a greedy plugin starves only itself, not a neighbor's cache. Rejected
alternative: a single shared pool with only a global cap (simpler but no
isolation; one plugin can evict everyone's data).

### 4.4 Where caps are configured
Default per-subdir + per-node caps in the manager's ConfigMap
(`wes-local-cache-manager-env`), overridable per node. Optionally, allow a plugin
to REQUEST a larger cache allocation via a `sage.yaml` field (analogous to
`resource:`), which SES records and the manager reads — but the manager's hard
ceiling always wins. (v1 can ship with fixed defaults and add per-plugin requests
later.)

### 4.5 Optional hardening: filesystem project quotas
Where `/media/plugin-data` is on XFS/ext4 with project quotas, WES could assign
each plugin subdir a project-ID'd hard byte cap so writes past it fail with
ENOSPC at the kernel — the strongest possible wall. BUT this is
filesystem-dependent and less portable than the manager-pod sweep. Lean:
**manager-pod sweep is PRIMARY** (works on any filesystem); project quotas are an
optional belt-and-suspenders where the fs supports them.

---

## 5. Node provisioning

The host dir `/media/plugin-data/local-cache` must be created at node setup, the
same place/way `/media/plugin-data/uploads` already is (the WES ansible /
node-setup that provisions `/media/plugin-data`). Permissions must allow the
manager (root/privileged) full control and plugin pods (various uids) to create
their own subdirs + read across them — align with how `/uploads` DirectoryOrCreate
is handled, plus the world-readable convention from §3.2.

---

## 6. How a plugin requests the mount TODAY (and the real schema gap)

Correction to Infra #9's original framing: the pluginSpec schema **already exposes
a hostPath mount field.** `datatype.PluginSpec` has
`Volume map[string]string` (plugin.go:44); SES mounts each `from→to` as a hostPath
into the pod (resourcemanager.go ~L776). So a job CAN request
`/media/plugin-data/local-cache → /local-cache` today. The real, narrower gaps:
1. **Requires a nodeSelector** — volume mounting errors out without `--selector`/
   `--node` (resourcemanager.go ~L807). Fine for pinned deployments; awkward for
   fleet-portable jobs.
2. **Unresolved root-ownership security TODO** — the code has a commented-out
   `IsOwnedByRoot` check (resourcemanager.go ~L777) intended to forbid mounting
   non-root-owned host dirs; until resolved, arbitrary hostPath mounting is a
   security concern the team has flagged.
3. **Undocumented** — no existing job YAML uses it; the field isn't in the docs.

So the ask on WES is NOT "add a mount field" (it exists) but: (a) provision the
cache dir + the manager DaemonSet, (b) document the `volume:` field for the cache
use case, and (c) ideally auto-mount `/local-cache` for any plugin that opts in
via a `sage.yaml` flag, so plugins don't hand-roll hostPaths (safer + resolves the
root-ownership concern by having WES own the path).

---

## 7. Migration & compatibility

- **image-sampler2 works UNCHANGED the moment the mount exists.** cache.py already
  resolves `/local-cache` first; today it silently falls to `/tmp`. Mount the dir
  and the producer/consumer loop lights up with zero code change — the whole point
  of having assumed `/local-cache` all along.
- Layer 1 primitive is additive to pywaggle2 (`cache_file`/`read_cache` beside
  `upload_file`); plugins that don't cache are unaffected.
- Layer 2 manager is a pure add — a new DaemonSet; it touches only
  `/media/plugin-data/local-cache`, never `/uploads`.

---

## 8. Open questions

1. **Default caps** — sensible per-subdir and per-node defaults for the manager
   (e.g. 2Gi/plugin, 20Gi/node)? Depends on node disk size; make it a ConfigMap.
2. **Per-plugin cache request** — ship v1 with fixed defaults, or add the
   `sage.yaml` cache-size request field immediately? Lean: fixed defaults first.
3. **Auto-mount opt-in** — should a `sage.yaml` flag (e.g. `local_cache: true`)
   make SES auto-mount `/local-cache` (WES-owned path, sidesteps the root-owner
   concern), rather than each job specifying a raw `volume:`? Lean: yes, this is
   the clean interface.
4. **Retention semantics** — is oldest-first (by capture-ts) the right blunt
   policy for Layer 2, or should it be largest-first / round-robin across plugins
   when the NODE cap (not a single subdir) is exceeded? Lean: per-subdir cap =
   oldest-first; node-cap breach = evict proportionally from the biggest
   over-cap offenders first.
5. **Cross-user read mechanics** — confirm on-node whether chmod-on-write suffices
   or whether a shared group / fsGroup is needed for consumer pods (IS-7 probe,
   once the mount exists).
