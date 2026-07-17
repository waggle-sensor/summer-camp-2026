# On-node plugin verification recipe (side-load → run → data-plane confirm)

Proven repeatable across image-sampler2 Stage 4d/5d/6d on H00F (Thor, aarch64).
This is the "prove it in the data plane, not just Running" workflow the user
insists on (Running ≠ working; crash-loops show Running).

## 0. Preconditions / invocation facts (see also pluginctl-sideload-and-node-build.md)
- `ssh USER@node-<VSN>.sage` then `export XDG_RUNTIME_DIR=/run/user/$(id -u)`.
- Use `sudo pluginctl` (root k3s cluster-admin config). Unprivileged pluginctl
  hardcodes the `default` namespace where beckman lacks pod-create RBAC.
- Volume-mounted pods MUST target a node: use `--selector zone=core` (the node
  label). `--node <hostname>` builds a node-affinity that does NOT match and the
  pod sticks Pending — selector is the reliable path.
- Credentials env-only: `--env-from <mode-600 file>`; NEVER on argv. Shred the
  file after (`shred -u`). Password never printed.

## 1. Build + import to k3s containerd
```
git clone -q --depth 1 https://github.com/flint-pete/image-sampler2.git /tmp/is2-build
cd /tmp/is2-build
podman build -t localhost/image-sampler2:<ver>-rc .
podman save localhost/image-sampler2:<ver>-rc -o /tmp/img.tar
sudo k3s ctr images import /tmp/img.tar && rm -f /tmp/img.tar
```
Confirm the Dockerfile COPYs every new module — a missing `COPY newmodule.py`
is a silent ImportError at run time, caught only on-node. (Bit us twice:
capture.py/cache.py in 4, heartbeat.py in 5.)

## 2. The host-mounted-cache producer trick (KEY TECHNIQUE)
`timeout N sudo pluginctl run …` cuts the log stream AND pluginctl tears the pod
down on stream exit — BUT a host `-v hostdir:/cache` mount PERSISTS the files.
So a bounded producer run leaves a real cache you can inspect / feed a consumer:
```
sudo mkdir -p /media/plugin-data/is2-scratch && sudo chmod 777 /media/plugin-data/is2-scratch
# fill a ring with ~3 real frames, then let timeout kill the stream+pod:
timeout 20 sudo pluginctl run -n prod --selector zone=core \
  --env-from /tmp/cam.env -v /media/plugin-data/is2-scratch:/cache \
  localhost/image-sampler2:<ver>-rc -- \
  --continuous 8 --stream top --cache-root /cache --cache-name X --cache-max-count 3 ...
ls -la /media/plugin-data/is2-scratch/X/top/    # files survive the pod
```
This also solves "/tmp not visible over SSH": mount the cache to a host dir and
observe the ring (counts, eviction, .tmp absence, EXIF via pluginctl exec piexif).

## 3. Data-plane confirmation (the actual proof)
Records/uploads a plugin publishes are queryable even for side-loaded pods
(job shows as `Pluginctl`). Query from anywhere (Flint or node):
```
START=$(date -u -d "20 minutes ago" +%Y-%m-%dT%H:%M:%SZ)
curl -s -m 30 -X POST https://data.sagecontinuum.org/api/v1/query \
  -H 'Content-Type: application/json' \
  -d "{\"start\":\"$START\",\"filter\":{\"name\":\"upload\",\"vsn\":\"H00F\",\"task\":\"<podname>\"}}"
```
- `filter.name` = a measurement (`upload`, `env.imagesampler.cache.count`, …);
  `filter.task` = the pluginctl `-n <name>`; `filter.vsn` = the node VSN.
- IDENTITY IS ATTACHED DOWNSTREAM: pods self-report the placeholder `vsn=NODE`,
  but Beehive routing rewrites records to the real `vsn=H00F` / `node=<hostid>`.
  So query by H00F even though the pod only knows NODE. (Confirms the
  "plugins do not self-identify" model — routing supplies vsn/gps.)
- Convert an ns record timestamp to check capture-vs-send:
  `python3 -c "import datetime;print(datetime.datetime.utcfromtimestamp(<ns>/1e9))"`.
  A `--from-cache` upload's RECORD timestamp must equal the ORIGINAL capture ts
  (from the cached filename), NOT the send time; `meta.upload_timestamp` carries
  the real send time. Verified live: record ts = capture ts, upload_timestamp
  later, `meta.source=from-cache`.

## 3b. Consumer-side e2e: producer → shared cache → CONSUMER (VERIFIED sage-yolo2 2.0.0, H00F 2026-07-14)
The above proves a PRODUCER/uploader. For a pywaggle2 CACHE CONSUMER (a plugin that
reads frames another plugin wrote and publishes derived measurements — e.g. YOLO
counts), run the pair back-to-back against the REAL shared cache mount:
```
# PRODUCER: image-sampler2 --continuous fills the shared WES cache with real frames
sudo pluginctl run --name prod --selector zone=core --env-from /root/cam.env \
  -v /media/plugin-data/local-cache:/local-cache \
  localhost/image-sampler2:<ver> -- \
  --continuous 10 --stream top_camera --name top \
  --cache-root /local-cache --cache-name hummingcam --cache-max-count 20 --vsn H00F
# CONSUMER: the GPU plugin reads those frames (NOTE the mandatory mem limit)
sudo pluginctl run --name cons --selector zone=core \
  --resource limit.memory=16Gi,request.memory=4Gi \
  -v /media/plugin-data/local-cache:/local-cache \
  -e WAGGLE_JOB_NAME=stage7 -e WAGGLE_TASK_NAME=sage-yolo2 \
  registry.sagecontinuum.org/<ns>/<consumer>:<ver> -- \
  --source cache --input /local-cache/hummingcam/top --every 0 --all-unseen --max-frames 5 ...
```
Key differences vs the producer recipe:
- **GPU consumers MUST set `--resource limit.memory=16Gi,request.memory=4Gi`** or
  the pod is OOMKilled (exit 137) at first inference — see the "GPU consumer
  OOMKilled" section in `pluginctl-sideload-and-node-build.md` for the full
  diagnosis. (`--resource resource.gpu=true` is INVALID; GPU is auto on Thor.)
- The shared cache is the REAL WES mount `/media/plugin-data/local-cache` (from
  `wes-local-cache-manager`), not a scratch dir — both pods mount it to `/local-cache`.
- Capturing the consumer's per-frame output before GC: pluginctl detaches its log
  stream early, so poll `sudo kubectl logs <n> -n default -c <n>` into a file until
  a marker appears (see the "CAPTURING a one-shot pod's FULL logs" section in
  pluginctl-sideload-and-node-build.md).

### Frame-anchored COUNTS confirmation (observation_ts = capture_ts) — the decisive check
A counting consumer publishes `env.count.total` (+ `env.count.<class>`) EVERY cycle
(even 0 = heartbeat), not `upload`. Confirm frame-anchoring in the data plane:
```
curl -s -X POST https://data.sagecontinuum.org/api/v1/query -H 'Content-Type: application/json' \
  -d '{"start":"-15m","filter":{"vsn":"H00F","name":"env.count.total"}}'
```
The record `timestamp` MUST equal the frame's CAPTURE time (matches the producer's
`<ns>-v2-<vsn>-<cam>.jpg` filename ns), NOT the inference time — proving the
consumer stamps observation time from the frame, so a backlog processed minutes
late still lands on the science timeline correctly. `meta` carries vsn/node
(downstream-attached), `plugin` (image ref), `task` (the `-n` name). SEEN-STORE
dedup proof: the consumer writes SHA256 `unique_id`s under the cache's reserved
`.state/` area; a SECOND run loads them ("N known"), skips those frames, and
processes only new ones — persists across pod restarts. Inspect on the host:
`sudo find /media/plugin-data/local-cache/.state -name seen -exec wc -l {} +`.

## 4. Liveness / dead-camera test (heartbeat plugins)
To prove a periodic liveness signal fires when the sensor is dead: relaunch
pointed at an unreachable camera IP with a short `--capture-timeout`. Captures
fail ("Connection refused") but heartbeats keep publishing on their grid with
count=0/status=skip — the "running but silent" case. Confirm both in the log AND
the data plane.

## 5. Teardown (always)
```
sudo pluginctl rm <pod> ; shred -u /tmp/cam.env
sudo rm -rf /media/plugin-data/is2-scratch /tmp/is2-build
# confirm clean + scheduler unharmed:
sudo k3s kubectl get pods -n default | grep -iE "is2" || echo "clean"
sudo k3s kubectl get pods -n default | grep -c "wes-plugin-scheduler.*Running"
```
The WES stack (scheduler/sciencerule-checker/scoreboard/rabbitmq/upload-agent)
must remain Running; birdnet/yolo are scheduler-cycled science jobs — a
side-loaded test in `default` does not disturb them.
```
