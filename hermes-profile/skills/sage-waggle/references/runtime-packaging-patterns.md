# Sage Edge Plugin Runtime & Packaging Patterns

Distilled from analysis of 4 production ECR plugins (cloud-motion-v1, sound-event-detection, avian-diversity-monitoring, object-counter) and the WES/k3s architecture documentation. June 2025.

## The One-Shot Execution Model

Sage plugins are NOT long-running daemons. The fundamental scheduling paradigm is **one-shot**: the scheduler fires a container, it does its work, and it exits. This is enforced for fair GPU/CPU sharing, resilience (crashed plugins are rescheduled), and reproducibility (each run is stateless).

### Execution flow

```
Edge Scheduler (cloud) → distributes job specs to target nodes
  ↓ (node agent polls)
WES / k3s (on-node):
  1. Node agent receives job
  2. containerd pulls image (if not cached)
  3. k3s creates a Kubernetes CronJob / Job
  4. Pod runs: init → process → publish → exit
  5. Pod marked Completed, garbage-collected
```

### Three scheduling modes

| Mode        | YAML                            | Behavior                              |
|-------------|---------------------------------|---------------------------------------|
| **Cronjob** | `schedule: "*/10 * * * *"`      | New one-shot pod every 10 min (most common) |
| **Lambda**  | `when: {name: ..., cond: ...}`  | Pod fires in response to data event   |
| **Always**  | `schedule: "always"`            | Continuous (rare, discouraged for GPU plugins) |

Cronjob is the dominant pattern. Each cron tick creates a fresh Kubernetes Job. The restart policy is `Never` — if it crashes, it stays crashed for that tick and the next tick creates a new pod.

### What this means for app.py

Follow the **Start → Process → Publish → Exit** pattern:

```python
with Plugin() as plugin:
    with Camera(args.stream) as cam:
        sample = cam.snapshot()
        # ... run inference ...
        plugin.publish("env.count.car", count, timestamp=sample.timestamp)
        # exit naturally
```

If you need multiple frames, loop with a fixed iteration count or timeout, then exit. The scheduler fires you again at the next cron tick.

## pywaggle `publish()` pitfalls (silent data loss)

### `meta` MUST be `dict[str, str]` — non-string values raise and drop the record

pywaggle's `Plugin.publish(..., meta={...})` validates the meta dict and raises
`TypeError: Meta must be a dictionary of strings to strings.` if ANY value is not
a `str`. Passing a float/int/bool in `meta` crashes the publish call. With the
one-shot `restartPolicy: Never` model, the exception kills the whole cycle —
nothing for that tick reaches the data API.

This is insidious because it can hide for the entire life of a plugin: a real
case had birdnet publish a per-detection record with float `start_time_s` /
`end_time_s` in meta. It threw on EVERY detection, so the plugin published ZERO
detections ever — yet the plugin "looked alive" because a SEPARATE summary
publish (which had no `meta`) succeeded as a heartbeat. So the heartbeat topic
flowed while the actual science topic was silently 100% lost.

```python
# ✗ WRONG — floats in meta; raises TypeError, record never lands
plugin.publish("env.detection.audio.x", conf, timestamp=ts,
               meta={"start_time_s": det["start_time"]})   # float!

# ✓ RIGHT — stringify every meta value
plugin.publish("env.detection.audio.x", conf, timestamp=ts,
               meta={"start_time_s": str(det["start_time"])})
```

The `value` (2nd positional arg) is fine as a number (float/int) — the
restriction is ONLY on `meta` values. `upload_file(..., meta=...)` has the same
rule.

**Diagnosis recipe** (when the data API shows a heartbeat/summary topic but the
real detection topics are empty): catch a live one-shot pod mid-run and look at
its logs for a `Traceback` right AFTER the "Classified/Detected N" line —
`kubectl logs -n ses <pod>`. Or reproduce locally without a broker using
`PYWAGGLE_LOG_DIR`, which exercises the real publish-validation path and writes
`data.ndjson`:
```bash
docker run --rm -e PYWAGGLE_LOG_DIR=/tmp/wlog -v $PWD:/data <image> \
  python3 /app/app.py --input /data/clip.wav ...   # then cat /tmp/wlog/data.ndjson
```
A clean run writes the per-detection records; the buggy build throws at the
publish line. When you fix one plugin, AUDIT the others' `meta={...}` /
`upload_file(meta=...)` calls for the same float-in-meta pattern.

## Container Lifecycle on the Node

Each Sage Wild node runs **k3s** (lightweight Kubernetes) with **containerd** as the container runtime.

### Pod lifecycle timeline

```
│ Image Pull    │ Container Start │ Your app.py runs  │ Cleanup │
│ 0-300s first  │ 1-5s            │ 10s - 5min        │ ~1s     │
│ 0s cached     │                 │                   │         │
```

- **Image Pull**: containerd checks local store. First run downloads every layer. After that, cached. A 15GB ML image can take minutes on constrained uplink.
- **Container Start**: k3s creates pod, mounts volumes, starts entrypoint. Plugin-base images set `ENTRYPOINT ["python3", "/app/app.py"]`.
- **Your app.py**: GPU available via NVIDIA device plugin. Camera via `waggle.data.vision.Camera`. Local filesystem is ephemeral.
- **Cleanup**: Pod exits as `Completed`. Image stays cached.

## Image Caching and Layer Reuse (Critical for ML plugins)

containerd stores images as content-addressable layers. When pulling an image:
1. Fetches manifest (tiny — just layer digests)
2. Checks each layer digest against local store
3. Only downloads new layers
4. Assembles from cached + new

### Typical ML plugin layer stack

```
Layer 1:  Ubuntu base              (~80 MB)   ← shared across plugins
Layer 2:  CUDA runtime             (~3 GB)    ← shared across GPU plugins
Layer 3:  PyTorch + dependencies   (~5 GB)    ← shared if same base
Layer 4:  Your code + pip packages (~500 MB)  ← plugin-specific
Layer 5:  Baked model weights      (~1-20 GB) ← plugin-specific
```

Two plugins sharing the same base image (e.g. both using `nvcr.io/nvidia/pytorch:24.06-py3`) only download layers 4-5 for the second plugin.

### imagePullPolicy defaults

| Image tag          | Default policy    | Behavior                    |
|--------------------|-------------------|-----------------------------|
| `my-plugin:0.1.0`  | `IfNotPresent`    | Pull once, cache forever    |
| `my-plugin:latest` | `Always`          | Check registry every time   |
| `my-plugin@sha256` | `IfNotPresent`    | Pull once (immutable)       |

**Always use explicit version tags, never `:latest`** for production plugins. With `:latest`, every cron tick triggers a registry check (and potentially a re-pull).

### Dockerfile layer ordering (critical for iteration speed)

Layers are cached top-down. If a layer changes, everything below is invalidated.

```dockerfile
# ✅ GOOD: Rarely-changing layers first, frequently-changing last
FROM nvcr.io/nvidia/pytorch:24.06-py3
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r /app/requirements.txt
RUN curl -L -o /app/models/yolo.pt <url>     # model (changes rarely)
COPY app.py /app/                              # code (changes often) — LAST

# ❌ BAD: Code before model
FROM nvcr.io/nvidia/pytorch:24.06-py3
COPY app.py /app/                              # ← changes often
RUN curl -L -o /app/models/yolo.pt <url>       # ← re-downloaded on every rebuild!
```

## Reference Plugin Analysis

### Common patterns across all 4 studied plugins

| Feature               | cloud-motion | sound-event | avian-div | object-counter |
|-----------------------|:------------:|:-----------:|:---------:|:--------------:|
| waggle Plugin ctx mgr | ✓            | ✓           | ✓         | ✓              |
| argparse CLI          | ✓            | ✓           | ✓         | ✓              |
| Model baked in image  | n/a          | ✓ (ADD)     | ✓ (ADD)   | ✓ (wget)       |
| Camera input          | ✓            | —           | ✓         | ✓              |
| Audio input           | —            | ✓           | ✓         | —              |
| Ontology-based names  | ✓            | ✓           | ✓         | ✓              |
| One-shot capable      | ✓            | ✓           | ✓         | ✓              |

### Base images used by reference plugins

| Plugin              | Base Image                                    | Notes                  |
|---------------------|-----------------------------------------------|------------------------|
| cloud-motion        | `waggle/plugin-base:1.1.1-base`               | CPU-only, OpenCV       |
| sound-event         | `waggle/plugin-base:1.1.1-base`               | CPU-only, TFLite       |
| avian-diversity     | `nvcr.io/nvidia/l4t-tensorflow:r32.4.4`       | Jetson-specific        |
| object-counter      | `waggle/plugin-base:1.1.1-ml-torch1.9`        | GPU, PyTorch 1.9       |
| our 3 plugins       | `nvcr.io/nvidia/pytorch:24.06-py3`            | Modern GPU, PyTorch 2+ |

### Model download patterns from reference plugins

- **sound-event**: `ADD https://web.lcrc.anl.gov/public/waggle/models/yamnet.tflite /app/`
- **avian-diversity**: `ADD https://web.lcrc.anl.gov/public/waggle/models/BirdNET_GLOBAL_6K_V2.4_Model_FP16.tflite /app/`
- **object-counter**: `RUN wget https://github.com/WongKinYiu/yolov7/releases/download/v0.1/yolov7.pt -O /app/yolov7.pt`
- **sound-event (legacy)**: `sage-cli.py storage files download` (commented out — migrated to direct URL)

All reference plugins host models on stable URLs (lcrc.anl.gov, GitHub releases). Our plugins use the same pattern.

## Cold-Start Optimization Checklist

1. **Minimize image size**: `pip install --no-cache-dir`, `apt-get clean`, multi-stage builds
2. **Profile imports**: `torch` import alone takes 3-5s. Heavy frameworks add up.
3. **Right-size the model**: YOLOv8n (6MB, ~1s load) vs YOLOv8x (130MB, ~3s) — match to science goal
4. **Warmup inference**: First inference triggers JIT compilation. Send a dummy input before real data.
5. **Share base images**: All our plugins use `nvcr.io/nvidia/pytorch:24.06-py3` — cached once on node.
