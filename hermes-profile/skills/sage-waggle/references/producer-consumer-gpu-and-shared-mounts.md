# Producer/consumer plugin architecture + WES cross-plugin shared filesystem

Hard-won design + platform facts from building "image-sampler2" (an enhanced
imagesampler fork) for node H00F (Thor, single GPU). Two reusable ideas:
(1) a producer/consumer split that fixes single-GPU contention, and (2) the
concrete WES facts that make cross-plugin file sharing on a node actually work.

## 1. Producer/consumer split — the fix for single-GPU contention

Problem (see also `scheduling-continuous-vs-oneshot-and-gpu-contention.md`): on a
single-GPU node you cannot run two always-on GPU model plugins. If each GPU plugin
also does its own camera sampling continuously, it HOLDS the GPU 24/7 and blocks
the others.

Fix: DECOUPLE acquisition from inference.
- PRODUCER: a cheap, CPU-only plugin (e.g. image-sampler2 `--continuous`) samples
  the camera on a fixed period and writes frames into a local, bounded ring cache
  on the node. It NEVER uploads and NEVER does inference/triggering. Pure producer.
- CONSUMER(S): GPU model plugins (YOLO/BioCLIP/BirdNet) wake on their own schedule,
  load the model ONCE, BATCH-infer N cached images, upload only the interesting
  ones, unload, and FREE the GPU between windows. Trigger plugins (audio event,
  remote alert) are also consumers: they read the cache and act.

Why it wins — amortize the model load over a batch:
- BioCLIP load ~10.4 s, inference ~1 s/img.
  - load->infer->exit per image: 10.4 + 1 = 11.4 s/img, GPU held throughout,
    ~5 img/min ceiling.
  - batched N=10: 10.4 + 10*1 = 20.4 s for 10 = ~2.04 s/img amortized, GPU held
    20.4 s then FREED (~5.6x throughput; GPU idle/shareable the rest of the window).
So one cheap CPU producer feeds many GPU consumers, and the GPU is time-shared
cleanly instead of hogged. This is the composable building-block model: keep the
sampler single-responsibility (produce), push upload/inference/trigger to consumers.

Corollary decisions that keep it clean:
- Continuous producer is LOCAL-ONLY (never uploads). Uploading is a consumer job.
- Periodic "one image to the cloud every N min" is solved by COMPOSITION, not by
  adding upload to the producer: run a second one-shot job on an SES cron that
  reads the newest cached image and uploads it via the existing one-shot upload
  path (a `--from-cache` source flag). No new upload logic; reuses the consumer
  read-from-cache pattern.
- Size the ring >= the longest trigger lookback (a lightning/wildfire trigger wants
  frames from seconds BEFORE the event; oldest-first eviction must not have dropped
  them yet).

## 2. WES cross-plugin shared filesystem — verified facts (H00F, edge-scheduler 0.28.0)

For a consumer plugin to read what a producer plugin wrote, files must live on a
HOST-BACKED mount shared across pods (each WES plugin pod has its own container FS
by default — pod A's files are invisible to pod B unless a hostPath is shared).

VERIFIED (live node inspection + edge-scheduler resourcemanager.go source):
- `/media/plugin-data/` exists on the node, backed by the root NVMe (persistent
  across pod restart AND node reboot; not pod-ephemeral).
- WES AUTO-MOUNTS, into EVERY plugin pod, a hostPath volume:
      host  /media/plugin-data/uploads/<JOB>/<NAME>/<TAG>
      pod   /run/waggle/uploads   (read-write)
  The uploads area is already structured per-plugin-instance on disk
  (e.g. `bioclip-species-classifier-5647/`, `birdnet-species-5645/`).
- Cross-pod visibility works BECAUSE it's a hostPath: what one pod writes on the
  host, another pod mounting the same host path reads directly.
- WES also supports user-declared volumes (`uservolume-N`) BUT the scheduler source
  warns they REQUIRE a nodeSelector or the pod fails to schedule. The auto uploads
  mount is the low-friction path.
- Plugin env WES injects (useful for self-identification): WAGGLE_APP_ID (=pod uid),
  HOST (=node name), WAGGLE_PLUGIN_HOST/PORT, and a mounted
  /run/waggle/data-config.json. Pod spec: ServiceAccount wes-plugin-account,
  RestartPolicy Never, ShareProcessNamespace=true, finished pods GC'd after ~60 s.
- `wes-data-sharing-service` is a RabbitMQ-based messaging/pubsub service, NOT a
  filesystem share (it has no host mounts). Do not mistake it for the shared FS.

CAVEAT — where to put a LOCAL-ONLY cache (two homes, pick deliberately):
- (A) under the auto uploads mount (/run/waggle/uploads): zero config, guaranteed
  present, persistent — BUT it's the tree the wes-upload-agent watches, so confirm
  the agent only uploads pywaggle-staged files (a specific sub-path), not
  everything under the mount, before using it for files you do NOT want uploaded.
- (B) a dedicated subtree (a uservolume-N, or a distinct host dir mounted rw into
  the producer and ro into consumers): cleanly separated, no accidental upload, but
  user volumes need a nodeSelector / a fixed host dir must be provisioned.
Lean (B) for a local-only ring so nothing is accidentally uploaded.

Uniqueness/discovery for a shared cache used by multiple instances:
- Key the cache path by a STABLE user-supplied `--cache-name`, NOT the SES job id
  (changes every resubmit, unguessable by a consumer) and NOT an opaque hash:
      <SHARED_ROOT>/<cache-name>/<camera>/ ...
  Two differently-configured samplers on one camera use two different cache-names.
- Consumers find caches by convention (SHARED_ROOT + known cache-name + camera).
  A runtime announcement (publish a Waggle record with the path, and/or a
  manifest.json in the cache root) is a nice later enhancement, not needed for v1.

## 3. POSIX safety for a ring cache read by other processes

- Concurrent read + evict is safe: a consumer that has OPENED a file keeps a valid
  fd even if the ring unlinks (evicts) it mid-read (inode persists until fd close).
- Write atomically: temp file -> fsync -> os.replace to the final name, so a
  consumer never sees a torn/half-written .jpg and eviction accounting only ever
  counts finished files.
- Consumers MUST tolerate ENOENT between listing and open (a file may be evicted in
  the gap) — treat as "already gone, skip" and copy/upload promptly rather than
  assume long-term residency.
- Evict oldest-first by the capture-timestamp prefix in the filename (authoritative
  order, no stat needed), so the cache always retains the MOST RECENT window —
  exactly what look-back triggers want.
