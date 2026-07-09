# On-node plugin verification recipe (side-load → run → data-plane confirm)

Proven repeatable across image-sampler2 Stage 4d/5d/6d on H00F (Thor, aarch64).
This is the "prove it in the data plane, not just Running" workflow the user
insists on (Running ≠ working; crash-loops show Running).

## 0. Preconditions / invocation facts (see also pluginctl-sideload-and-node-build.md)
- `ssh beckman@node-H00F.sage` then `export XDG_RUNTIME_DIR=/run/user/$(id -u)`.
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
