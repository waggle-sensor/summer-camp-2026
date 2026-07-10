---
name: sage-waggle
description: "Sage Continuum & Waggle: edge computing platform — plugin dev, ECR submission, data APIs, job scheduling, node management, testing."
tags: [edge-computing, iot, sage, waggle, scientific-compute]
triggers:
  - User mentions Sage, Waggle, sagecontinuum, waggle-sensor, Beehive, Beekeeper, WES
  - Tasks involving edge computing plugins that publish sensor data
  - Querying environmental/scientific sensor data from distributed nodes
  - Scheduling jobs on edge nodes (sesctl, pluginctl)
  - Working with sage-data-client or pywaggle
  - Developing Docker-based edge plugins
  - Using the Sage MCP server
globs: ["*sage*", "*waggle*", "*plugin*sage*", "*beehive*"]
---

# Sage Continuum & Waggle Platform

## Architecture Overview

1. **Edge Nodes** — ARM64/x86; WES/k3s. Refs:`node-ssh-access-and-gpsd-probe`,`node-identity-and-upload-contract`,`pywaggle2-nodeinfo-gps-design`,`pluginctl-sideload-and-node-build`,`image-metadata-naming-and-eventlog-linking`,`storage-upload-health-verification`,`thor-arm64-deploy-pipeline`,`cloud-trigger-watchers`,`scheduling-continuous-vs-oneshot-and-gpu-contention`,`local-cache-ring-buffer`,`wes-node-service-daemonset-sideload`,`continuous-producer-patterns`,`plugin-design-doc-workflow`,`n
2. **Beehive (Cloud)** — Receives data uploads, stores in time-series DB + object store. Runs RabbitMQ message bus.
3. **Beekeeper** — Node identity, registration, provisioning, reverse SSH tunnels for management.

## Key APIs

| API | Endpoint | Auth | Notes |
|-----|----------|------|-------|
| Data query | `POST https://data.sagecontinuum.org/api/v1/query` | None (public) | JSON body: `{"start":"-1h","tail":5}`, returns NDJSON |
| Manifests | `GET https://auth.sagecontinuum.org/manifests/` | None | Trailing slash required. Returns all node metadata (2MB+) |
| Edge Scheduler | `https://es.sagecontinuum.org` | Bearer token | Job submission/management |
| MCP Server | `https://mcp.sagecontinuum.org/mcp` | None (read-only); Bearer token for job submission | 29 tools — see references/mcp-tools.md |
| Portal | `https://portal.sagecontinuum.org` | Browser login | Node management, token generation |
| ECR (Edge Code Repo) | `https://portal.sagecontinuum.org/apps` | Browser login | Plugin registry |

Auth tokens: get from `portal.sagecontinuum.org/account/access`. Format: `Authorization: Bearer {token}`.

## Plugin Development

> **Camp default (Thor):** prefer `sudo pluginctl build .` → `sudo pluginctl run` for on-node development. Start with `references/pluginctl-camp-guide.md`. Use raw `podman build` only for ECR-bypass side-load workflows (see `references/pluginctl-sideload-and-node-build.md`).

Plugins are Docker containers using pywaggle. Minimal pattern:

```python
from waggle.plugin import Plugin
import time

with Plugin() as plugin:
    while True:
        value = read_sensor()
        plugin.publish("env.measurement", value, meta={"units": "C"})
        time.sleep(30)
```

### Plugin file structure
- `app.py` — main application
- `Dockerfile` — based on `waggle/plugin-base:1.1.1-base` (ARM64) or `-ml` variant for GPU
- `.dockerignore` — excludes tests/, ecr-meta/, jobs/, __pycache__/, *.pyc, *.md, .git/ from Docker build context
- `sage.yaml` — metadata (name, description, version, authors, resources)
- `ecr-meta/` — ECR submission metadata
- `overview.md` — pedantic/instructive documentation (mini tutorial style)
- `jobs/` — per-plugin job YAMLs for edge scheduler deployment (self-contained)
- `tests/` — self-contained test suite (local test with real GPU inference, test images, harness copy, run script). See `references/testing-patterns.md`

### Camera & Microphone (pywaggle abstractions)
```python
from waggle.data.vision import Camera
cam = Camera("bottom_camera")     # Named (resolved via node data config — only on real Sage nodes)
cam = Camera("rtsp://admin:pass@192.168.1.100:554/h264Preview_01_main")  # RTSP IP camera
cam = Camera("/path/image.jpg")   # Static image — bare path, works on host only (NOT in Docker — see pitfall below)
cam = Camera("file:///path/image.jpg")  # Static image in Docker (bare paths trigger WES config lookup → FileNotFoundError)
sample = cam.snapshot()            # ImageSample: .data (numpy HWC RGB), .timestamp (ns), .save()

from waggle.data.audio import Microphone
mic = Microphone("my_microphone")
sample = mic.record(duration=5)    # AudioSample: .data (numpy), .timestamp, .save()
```

### Audio Plugin Development

For audio-based plugins (bird classification, sound event detection),
the pattern differs from vision plugins:

**Audio input modes:**
1. **pywaggle Microphone** — `Microphone("mic_name").record(duration=3)` for named node microphones
2. **Direct ALSA/PulseAudio** — `sounddevice` or `pyaudio` for direct recording on host
3. **File-based** — `--audio-dir` flag for batch testing against WAV/MP3 files
4. **Network camera audio via `--camera URL`** — extract audio from IP camera via ffmpeg. The `--camera` CLI flag accepts any ffmpeg-compatible audio source URL. The plugin auto-detects the stream type and adds appropriate ffmpeg flags. See `references/camera-audio-capabilities.md` for the full camera comparison. Supported patterns:
   ```bash
   # Mobotix MxPEG (auto-detected by "faststream" + "MxPEG" in URL, adds -f mxg)
   --camera "http://user:pass@IP/control/faststream.jpg?stream=MxPEG&needlength"

   # RTSP (auto-detected by rtsp:// scheme, adds -rtsp_transport tcp)
   --camera "rtsp://user:pass@IP/profile1/media.smp"

   # Any HTTP audio stream
   --camera "http://IP/audio.cgi"
   ```
   **IMPORTANT**: Mobotix M16 cameras may refuse RTSP (port 554 closed) but serve audio fine via MxPEG HTTP. Always try the MxPEG URL first. Tested: M16 delivers pcm_alaw at 8 KHz (4 KHz Nyquist) — marginal for BirdNET, which needs frequencies up to 8-15 KHz. A USB mic at 48 KHz is significantly better. pywaggle's `Microphone` class does NOT support network cameras — the plugin uses subprocess ffmpeg for camera audio.

**Key differences from vision plugins:**
- Audio chunks are typically 3 seconds (vs single-frame snapshots for vision)
- Sample rate matters: BirdNET requires 48 kHz, resampling if needed
- Model formats: TFLite (CPU, ARM64) vs PyTorch (GPU); GPU inference on ARM64
  is not always available (see BirdNET ARM64 limitation)
- Audio files can be large — consider recording to tmpfs and cleaning up
- Noise rejection: most audio classifiers have "non-event" classes for
  filtering environmental noise, human speech, etc.

**BirdNET V2.4 integration pattern (`pip install birdnet`):**
```python
import birdnet

# Load models (auto-download ~77MB acoustic + ~46MB geo on first use)
model = birdnet.load("acoustic", "2.4", "tf")
geo = birdnet.load("geo", "2.4", "tf")

# Species filtering by location + week
species = geo.predict(lat, lon, week=22, min_confidence=0.03)
species_set = species.to_set()  # NOT to_list()

# File-based prediction
predictions = model.predict(
    "recording.wav",
    top_k=5,
    default_confidence_threshold=0.25,  # NOT min_confidence
    sigmoid_sensitivity=1.0,
    custom_species_list=species_set,
    overlap_duration_s=0.0,
    bandpass_fmin=0,        # low-freq cutoff Hz (e.g. 150 to cut wind)
    bandpass_fmax=15000,    # high-freq cutoff Hz (e.g. 4000 for 8kHz camera mic)
    batch_size=1,           # increase for parallel processing of long recordings
)
df = predictions.to_dataframe()
# Columns: input, start_time, end_time, species_name, confidence
# species_name format: "Scientific name_Common name"
```

**API pitfalls discovered:**
- `model.predict()` uses `default_confidence_threshold`, NOT `min_confidence`
- `geo.predict()` returns `GeoPredictionResult` — use `.to_set()` (not `.to_list()`)
- Model auto-downloads on first use to `~/.local/share/birdnet/`
- No `__version__` attribute on the birdnet module
- `birdnet.load("acoustic", "2.4", "tf")` — the `"tf"` backend uses TFLite on ARM64 (CPU only, no GPU)
- Audio plugin Dockerfile should use `python:3.12-slim` (not NVIDIA base) since BirdNET is CPU-only on ARM64

**Audio plugin app.py pattern (proven in birdnet repo):**
- Wrap the model in a classifier class (e.g. `BirdNETClassifier`)
- Three audio source modes via CLI flags (in priority order):
  1. `--input <file>` — read from a local audio file (testing)
  2. `--camera <url>` — capture from network camera via ffmpeg subprocess
  3. (default) — record from USB microphone via pywaggle `Microphone`
- The `--camera` flag accepts any ffmpeg-compatible URL; auto-detects Mobotix MxPEG
  (adds `-f mxg`) and RTSP (adds `-rtsp_transport tcp`). Credentials in URL are
  masked in log output (splits on `@`, shows only the host portion).
- `record_from_camera()` function: spawns ffmpeg, converts to 48 KHz mono WAV in tmpdir,
  raises RuntimeError on ffmpeg failure or empty output. Cleanup via shutil.rmtree in finally block.
- Support `--dry-run` for testing without pywaggle (import Plugin only when needed)
- Support `--interval` for gap between cycles + `--num-recordings` for bounded runs
- `--num-recordings N` (default 1) = run exactly N cycles then exit; `--num-recordings 0` = loop forever (requires `--interval > 0`)
- This matches the old plugin's `--num_rec` + `--silence_int` semantics:
  old: `analyze.py --num_rec 6 --sound_int 5 --silence_int 1`
  new: `app.py --num-recordings 6 --duration 5 --interval 1`
- Publish per-species detections + JSON summary per cycle
- Topic format: `env.detection.audio.<scientific_name>` (lowercase, underscored)
- eBird geo-filtering is fully automatic for live deployments: `--lat`/`--lon` default to -1 which triggers auto-detection from the node manifest (`/etc/waggle/node-manifest-v2.json`). `--week` defaults to `auto` (calculate BirdNET week from current date: `(month-1)*4 + min(4, ceil(day/7.5))`, range 1–48). Resolve both at startup before constructing the classifier, so each scheduler invocation gets the correct location and week. Use explicit values to override for testing (`--lat 41.72 --lon -87.98 --week 25`). Use `--week -1` for year-round (no seasonal filter). The `--week` argparse type should be `str` (not `int`) to accept both `auto` and numeric values.
- Use `argparse.ArgumentDefaultsHelpFormatter` + grouped args (audio, model, location, runtime)
- Clean up temp recording files in `finally` blocks (record to tmpdir, shutil.rmtree after)
- Main loop refactored into `run_cycle(plugin=None)` + `run_loop(plugin=None)` —
  eliminates the old duplicate run_once/run_with_plugin code paths

**Audio plugin Dockerfile differs from vision plugins:**
- Base image: `python:3.12-slim` (not NVIDIA — BirdNET is CPU-only on ARM64)
- System deps: `ffmpeg libsndfile1 libasound2-dev`
- Pre-download models at build time: `RUN python3 -c "import birdnet; birdnet.load(...)"`
- Image size: ~2.9 GB (TensorFlow) vs ~10+ GB for vision plugins on NVIDIA base
- No GPU, no CUDA, no pip constraints file needed

See `references/audio-classification-models.md` for the full model survey.

**Camera device resolution** (`resolve_device()` chain):
1. Named stream (no `://`) → WES data config lookup (`/run/waggle/data-config.json`, Sage nodes only)
2. URL with scheme (`rtsp://`, `http://`) → passed directly to `cv2.VideoCapture()`
3. `file://path` → local file
4. Path object → local file

Named cameras (`bottom_camera`, `top_camera`) are aliases defined in the node's `/run/waggle/data-config.json` — a JSON array where each entry has `match.id` (the name) and `handler.args.url` (the actual RTSP/HTTP URL). This config is managed by WES and only exists on real Sage nodes.

For IP cameras not registered in WES (e.g. a Reolink on the same network), pass the RTSP URL directly to `--stream`. See `references/camera-rtsp-patterns.md` for vendor-specific URL formats, data-config.json format, Docker-on-Thor QA testing workflow, and troubleshooting.

### Plugin CLI input modes
Plugins support four input modes via argparse:
1. **`--stream <camera|rtsp|image>`** — live camera, RTSP URL, or single test image (default: `bottom_camera`)
2. **`--image-dir <path>`** — batch-process all images in a directory (overrides `--stream`)
3. **`--snapshot-url <http-url>`** — fetch a JPEG snapshot from an HTTP URL each cycle (overrides `--stream`). Works with Reolink CGI API, generic IP camera snapshot endpoints, or any URL returning a JPEG. Credentials go in the query string. See `references/reolink-http-snapshot.md`.
4. **`--continuous Y|N`** — loop (camera/snapshot-url) or single-shot. **WARNING**: the main loop's `if continuous != "Y": break` must be guarded with `and not using_image_dir` — otherwise `--image-dir` mode only processes the first image. See Pitfalls.

**Note**: Not all plugins implement `--image-dir`. YOLO and BioCLIP have it; vLLM only has `--stream` (accepts a camera name, RTSP URL, or single image path). For batch testing a plugin without `--image-dir`, loop in shell: `for img in tests/test-images/*.jpg; do python3 app.py --stream "$img" --continuous N; done` — but note each invocation may restart expensive resources (e.g. vLLM server subprocess).

### Exposing third-party library parameters
When a plugin wraps a third-party ML library (Ultralytics YOLO, vLLM, etc.), expose the library's key tuning parameters as CLI flags rather than hardcoding them. Pattern:
1. Add argparse flags with descriptive help text including the default value and a URL to the upstream docs
2. Pass the flag values through to the library's API call (e.g. `model(frame, imgsz=args.imgsz, half=args.half, ...)`)
3. Document all flags in overview.md's Configuration Reference table with consistent `Flag | Type | Default | Description` columns
4. Add a callout linking to the upstream docs page (e.g. `https://docs.ultralytics.com/modes/predict/#inference-arguments`)
5. Add corresponding entries to sage.yaml's `inputs:` section

Example YOLO flags exposed from Ultralytics: `--imgsz` (input resolution), `--half` (FP16), `--max-det` (max detections), `--augment` (TTA), `--agnostic-nms` (class-agnostic NMS). Each help string includes a link to Ultralytics docs so students can read the full parameter reference.

Use `iter_image_dir()` helper to yield `(path, frame, timestamp)` tuples from a directory, matching the Camera snapshot interface. Always filter by `IMAGE_EXTENSIONS` set. See `templates/ml-plugin-app.py` for the full pattern.

### Plugin publish patterns
```python
with Plugin() as plugin:
    plugin.publish("env.temperature", 23.5)
    plugin.publish("env.count.car", 12, timestamp=ts, meta={"camera": "bottom", "model": "yolov7"})
    plugin.upload_file("annotated.jpg")  # Upload large files (images, video)
```

**Meta value rule**: all values in `meta={}` must be `str`. pywaggle's `valid_meta()` raises ValueError on int/float/bool. Always `str()` wrap numeric meta.

### Self-describing publish records
When publishing aggregate records (e.g. `env.count.total`), include the full class breakdown in meta so each record is self-describing without cross-referencing per-class records:
```python
classes_summary = ",".join(f"{c}:{n}" for c, n in sorted(counts.items()))
plugin.publish("env.count.total", total, timestamp=ts,
               meta={"camera": source_name, "model": args.model,
                      "classes": classes_summary if classes_summary else "none",
                      "num_classes": str(len(counts))})
```
Result: `{"name":"env.count.total","value":3,"meta":{"classes":"bottle:1,person:2","num_classes":"2",...}}`

### Local testing (no node required)
```bash
export PYWAGGLE_LOG_DIR=./test-run
python3 app.py --stream test-image.jpg --continuous N
cat test-run/data.ndjson    # Published measurements captured here (NDJSON: one JSON object per line)
ls test-run/uploads/        # Uploaded files captured here as {timestamp}-{original_name}
```

`PYWAGGLE_LOG_DIR` is a built-in pywaggle feature (not custom code). When set, pywaggle redirects all `plugin.publish()` to `data.ndjson` and all `plugin.upload_file()` to `uploads/` inside that directory instead of sending to Beehive. **Without it, pywaggle tries to write to `/run/waggle/uploads/` which only exists on real nodes** — on dev machines you get `PermissionError: [Errno 13] Permission denied: '/run/waggle'`. The local test runners set it automatically; when running `app.py` directly, always `export PYWAGGLE_LOG_DIR=./output/<name>` first.

**Important**: all meta dict values MUST be strings. `plugin.publish("topic", 42, meta={"count": str(n)})` — not `{"count": n}`.

For testing ML plugins, see `references/testing-patterns.md`. All tests require GPU and run real model inference — no mocked unit tests. Each plugin has a self-contained `tests/` directory with its own test file, test images, harness copy, and `run-tests.sh`. A top-level `tests/run-all-tests.sh` auto-discovers and runs all plugin tests (GPU required). Test images live in `plugins/<name>/tests/test-images/` (flat directory, committed to git). All plugins share the same set of real test images — no synthetic generation step needed.

### pluginctl deploy vs docker run: where data goes

- **`docker run` with `-e PYWAGGLE_LOG_DIR=/output`**: data stays local. `plugin.publish()` writes to `data.ndjson`, `plugin.upload_file()` writes to `uploads/` inside the mounted volume. Nothing reaches Beehive.
- **`pluginctl deploy` (no PYWAGGLE_LOG_DIR)**: data goes to the real Sage pipeline. `plugin.publish()` sends measurements via RabbitMQ → Beehive → time-series DB (queryable at `data.sagecontinuum.org`). `plugin.upload_file()` sends files to the object store (Open Storage Network, S3-compatible). This is production data flow.

Use `docker run` + `PYWAGGLE_LOG_DIR` for testing/debugging. Use `pluginctl deploy` for real deployments.

### Plugin CLI tools (on-node via SSH)
```bash
ssh waggle-dev-node-V032           # Dev nodes use V0xx format
sudo pluginctl build .             # Build Docker image from current dir
sudo pluginctl deploy -n my-counter 10.31.81.1:5000/local/my-plugin  # Deploy (use descriptive names — visible across Sage)
sudo pluginctl ps                  # List running plugins
sudo pluginctl logs <plugin-id>    # View logs (sudo required on Thor)
sudo pluginctl rm <plugin-id>      # Remove plugin
```
Note: ALL pluginctl commands require sudo on Thor (k3s kubeconfig is root-only).

### Docker base images (waggle/plugin-base on Docker Hub)
| Image tag | Use case | Size (approx) | Arch |
|-----------|----------|---------------|------|
| `1.1.1-base` | Minimal Python, no ML | ~280MB | multi-arch |
| `1.1.1-ml` | ML with CUDA | ~1.6GB arm64 / ~3.5GB amd64 | multi-arch |
| `1.1.1-ml-torch1.9.0` | PyTorch 1.9 | ~2.6GB arm64 / ~5.3GB amd64 | multi-arch |
| `1.1.1-ml-tensorflow2.3-arm64` | TensorFlow 2.3 | ~1.2GB | arm64 only |
| `1.1.1-ml-tensorflow2.3-amd64` | TensorFlow 2.3 | ~2.6GB | amd64 only |
| `1.1.1-ml-dev` | Dev/debug ML | ~1.6GB | arm64 |
| `1.1.1-ros2-foxy` | ROS2 robotics | varies | varies |

### NVIDIA base images (GPU ML plugins)

For modern ML models (YOLO 8+, BioCLIP, vLLM, transformers), use NVIDIA PyTorch images instead of waggle/plugin-base:

| Image | PyTorch | CUDA | GPU Support | Notes |
|-------|---------|------|-------------|-------|
| `nvcr.io/nvidia/pytorch:25.08-py3` | 2.8 | 13.0 | **Blackwell native: sm_110 (Thor) + sm_120/sm_121 (DGX Spark)** | **Recommended — covers both Thor and DGX Spark** |
| `nvcr.io/nvidia/pytorch:25.04-py3` | 2.7 | 12.9 | sm_120/sm_121 only — **NO sm_110** | ⚠️ Fails on Thor ("sm_110 is not compatible") |
| `nvcr.io/nvidia/pytorch:25.03-py3` | 2.7 | 12.8.1 | Blackwell sm_120 only | No Thor support |
| `nvcr.io/nvidia/pytorch:25.01-py3` | 2.6 | 12.8 | Blackwell sm_120 (first) | Minor caveats (cuSPARSELt), no Thor |
| `nvcr.io/nvidia/pytorch:24.06-py3` | 2.4 | 12.4 | **Hopper max (sm_90)** | ⚠️ **WRONG for Blackwell** — silently falls back to CPU |
| `nvcr.io/nvidia/l4t-pytorch:*` | varies | varies | Jetson-specific | ARM64 only |

**CRITICAL**: On Blackwell GPUs, using `24.06-py3` causes PyTorch to silently fall back to CPU — inference appears to hang (extremely slow). On Thor nodes specifically, `25.04-py3` also fails (no sm_110 cubins). Always use `25.08-py3` or newer for any deployment targeting both DGX Spark and Thor. The 25.08 image requires driver R575+ (DGX Spark: 580.159, Thor: 580.00 — both compatible).

All NGC PyTorch containers are multi-arch (AMD64 + ARM64 SBSA) via manifests — `docker pull` auto-selects the right architecture. The `pytorch/pytorch:*` Docker Hub images are AMD64-only (no ARM64).

Pre-download model weights at build time to **explicit paths** (edge nodes may lack internet). Use `curl -L -o /app/models/<name>.pt <url>` for YOLO, `huggingface-cli download` for HF models. Do NOT rely on ultralytics auto-download (caches to `~/.config/Ultralytics/` — path changes between versions). Set `TRANSFORMERS_OFFLINE=1` and `HF_DATASETS_OFFLINE=1` in Dockerfile. See `references/ml-plugin-patterns.md` for baking patterns and the yolov7-fire ECR reference.

### "Further Reading" appendix pattern
Each plugin's overview.md should end with a "Further Reading" appendix that helps students go beyond the plugin's scope. Topics to cover:
1. **Custom-trained models** — how to fine-tune on domain-specific data and deploy with `--model custom.pt`
2. **Temporal analysis** — the plugin's limitations (single-frame, no tracking) and how the library supports tracking/temporal features
3. **Other tasks** — table of the library's task modes (detect, segment, pose, classify) with use cases, even though the plugin only uses one
4. **Relevant blog posts / papers** — links to upstream vendor articles showing real-world applications in the plugin's domain

This is especially important for student-facing docs. The plugin demonstrates one use case; the appendix shows the frontier.

### Design principle: self-contained teaching units
Each plugin should be independently explorable by a student. A student can copy any single plugin directory out of the monorepo and have everything needed to understand, test, and deploy it: app code, Dockerfile, metadata, documentation, job specs, and tests. Shared infrastructure (venv, top-level test runner) is the exception, not the rule. When in doubt about where a file belongs, put it inside the plugin directory.

### Design principle: no cross-plugin dependencies for ECR
Each plugin is submitted to ECR as an independent entry. Verify before submission: (1) app.py imports only stdlib + pip packages, no sibling plugin imports, (2) Dockerfile COPYs only requirements.txt and app.py from its own directory, (3) no relative paths reaching into other plugin dirs, (4) test_harness.py is copied (not symlinked) into each plugin's tests/ dir. Run `grep -rn 'other-plugin-name' plugins/this-plugin/` to verify.

### Build pipeline (Makefile)
Each standalone plugin repo should have a Makefile with at minimum:
```makefile
IMAGE   := plugin-name
VERSION := 0.1.0
TAG     := $(IMAGE):$(VERSION)

build:    docker build -t $(TAG) .
test:     build test-docker      # default target: build + validate
test-docker:  bash tests/run-tests.sh --docker
test-native:  bash tests/run-tests.sh
clean:    docker rmi $(TAG) 2>/dev/null || true
```
`make test` is the single command for build + validate. `make help` with self-documenting `## comment` targets. Exit code 0/1 for CI integration. NOTE: no `audio:` or `download:` targets — all test assets (images AND audio) must be committed to git. No runtime downloads.

### Standalone repo structure (proven pattern for ECR)
Each plugin repo should match this layout:
```
sage-<plugin>/
├── app.py                 — main application
├── Dockerfile             — NVIDIA base, pip constraints, model bake, patch scripts
├── DOCKER-BUILD.md        — build, test, deploy, ECR submission guide
├── DEPLOY-AND-RUN.md      — pluginctl one-shot test + sesctl scheduled deployment guide
├── THOR-TESTING.md        — quick start for Thor node testing
├── requirements.txt       — pip dependencies
├── sage.yaml              — ECR metadata, inputs, version
├── overview.md            — pedantic tutorial-style documentation
├── .gitignore             — tests/output/, output/, *.pt, __pycache__, ._*, .DS_Store
├── .dockerignore          — tests/, ecr-meta/, jobs/, *.md, .git/
├── patch_pybioclip.py     — (BioCLIP only) pybioclip monkey-patch
├── ecr-meta/              — ECR submission materials (6 files)
├── jobs/                  — per-plugin job YAMLs
└── tests/
    ├── run-tests.sh       — standalone test runner (no monorepo deps)
    ├── test_<name>_local.py — real GPU inference test
    ├── test_harness.py    — test utilities (copied, not shared)
    ├── test-images/       — committed test images
    └── output/            — gitignored test output
```
`run-tests.sh` must work standalone — no references to monorepo venv paths or parent directories. The test script should use the system Python or a local venv, not assume `../../tests/.venv` exists.

### Template repos
- `waggle-sensor/edge-app-template`
- `waggle-sensor/cookiecutter-sage-app`

## Container Runtime & Scheduling Model

Sage plugins follow a **one-shot execution model**: the scheduler fires a container, it processes, publishes, and exits. Pods are ephemeral — no persistent filesystem between runs. One-shot cron is standard; continuous pods are the exception (see `references/job-scheduling-and-liveness.md`). Publish a heartbeat every cycle or quiet jobs look dead. arm64/Thor: portal build crashes (QEMU), push denied — build local+sideload, see `references/ecr-arm64-thor-deployment.md`. Three scheduling modes:

| Mode | YAML | Use case |
|------|------|----------|
| Cronjob | `schedule: "*/10 * * * *"` | Most common — periodic sampling |
<!-- Scheduling debug + Reolink/sesctl gotchas: references/job-scheduling-and-debugging.md -->

| Lambda | `when: {name: ..., cond: ...}` | Data-driven triggers |
| Always | `schedule: "always"` | Continuous (rare, discouraged for GPU) |

k3s + containerd cache Docker image layers locally after first pull. Two plugins sharing the same base image (e.g. both on `nvcr.io/nvidia/pytorch:24.06-py3`) only download unique layers for the second one. **Always use explicit version tags**, never `:latest` — with `:latest`, every cron tick triggers a registry check.

**Dockerfile layer ordering matters**: place rarely-changing layers (base, requirements, model weights) BEFORE frequently-changing layers (app.py). Changing a layer invalidates everything below it. Put `COPY app.py /app/` as the LAST layer so code changes don't trigger model re-downloads.

See `references/runtime-packaging-patterns.md` for full details: pod lifecycle timeline, containerd caching mechanics, imagePullPolicy defaults, cold-start optimization checklist, and analysis of 4 production reference plugins.

## Job Scheduling (sesctl)

### Science rule syntax
Format: `action : condition`

**Actions:**
1. `schedule(image)` — run a plugin container
2. `publish(topic, value)` — publish a message
3. `set(variable, value=X)` — set a variable

**Condition functions:**
1. `v(measurement, sensor=, since="-1h")` — get measurement value
2. `time(unit)` — current time ("hour", "minute", etc.)
3. `cronjob(name, crontab)` — cron schedule (name must be unique per job)
4. `after(name, since="-1d")` — true after a named event
5. `rate(measurement, since, window, unit)` — rate of change

Example rules:
```
schedule(object-counter): cronjob('run-counter', '*/5 * * * *')
schedule(object-counter): v('env.temperature') > 30.0
```

### Job YAML (see templates/job.yaml for full example)

### sesctl CLI
```bash
export SES_HOST=https://es.sagecontinuum.org
export SES_USER_TOKEN=<token-from-portal>
sesctl create -f job.yaml      # flag is -f/--file-path, NOT --from-file; returns numeric job ID
sesctl stat                    # list jobs; sesctl stat -j <id> for one
sesctl submit -j <job-id>      # submit/activate by numeric ID, NOT by name
sesctl rm -j <job-id>          # remove by ID
```
**See `references/job-scheduling-and-liveness.md`** for: ECR app metadata vs Docker image (both must exist for SES — two distinct failure modes), one-shot cron vs continuous pods, pod namespace meaning (default=pluginctl, ses=scheduler), heartbeat/observability pattern, sesctl flag corrections, sage.yaml float type reality, avian-diversity-monitoring baseline schedules, and BioCLIP cold-start considerations.

`create` returns a numeric ID; capture it. Always run `sesctl <subcmd> --help` — this CLI's surface drifts from the published web docs.

> **Deployment model, namespace diagnostics, ECR gate, reading job schedules:**
> see `references/deployment-and-diagnostics.md`. Quick diagnostics:
> pods in the `ses` namespace = scheduler-launched (official); `default`
> namespace = hand-deployed via pluginctl (a `default` pod with multi-day uptime
> is a continuous test pod, NOT a scheduled job). `sesctl submit` requires the
> app to be registered in the ECR **catalog** (portal build) even though
> `pluginctl`/docker pull succeed without it — hence `400 ... does not exist in
> ECR` on submit. Most Sage jobs are cron one-shot, not long-running; weigh
> cold-start vs warm-pod before choosing `--continuous Y`.
> **Reolink audio auth** (BirdNET etc.): FLV/BCS needs creds as query params
cron-job liveness checks — see `references/job-scheduling-and-liveness.md`.**

## Data Access (sage-data-client)

```python
import sage_data_client

df = sage_data_client.query(
    start="-1h",
    filter={"name": "env.temperature", "vsn": "W030"}
)
# Returns pandas DataFrame with: timestamp, name, value, meta (sensor, vsn, node, plugin)
```

### curl (no Python needed)

```bash
curl -s -X POST https://data.sagecontinuum.org/api/v1/query -d '
{
  "start": "-1h",
  "filter": {
    "vsn": "H00F",
    "name": "env.count.*"
  }
}'
```

Returns NDJSON (one JSON object per line). The data API is public — no auth needed.

Filters: `name` (measurement), `sensor` (hardware), `vsn` (node ID), `plugin` (source plugin). Supports `*` wildcards.

Large files (images, audio): stored on Open Storage Network (S3-compatible object store), not in time-series DB.

## Triggers

- **Cloud-to-edge**: data arrival in Beehive triggers edge job (Lambda Triggers)
- **Edge-to-cloud**: edge data triggers HPC/cloud compute via sage-data-client polling
- **External notifications (Slack, email, etc.)**: run a watcher script externally that polls the data API and reacts. Containers on Sage nodes are network-restricted and cannot reach external services. Host processes on some nodes (e.g. Thor via SSH) CAN reach external URLs — but the recommended pattern is a cloud-side watcher, not a host-side process. See `references/cloud-trigger-notifications.md` for the full pattern, Slack webhook + image upload examples, secret management, and reference implementations (hummingbird-watcher, wildfire-trigger, severe-weather-trigger).

## GitHub Organizations

- `sagecontinuum` — 26+ repos (sage-data-client, sage-gui, sage-cli, sesctl, beekeeper)
- `waggle-sensor` — 80+ repos (pywaggle, waggle-edge-stack, edge-scheduler, pluginctl, plugin-base, virtual-waggle)

## Hermes Native MCP Integration

Wire up the Sage MCP server as a native Hermes tool so all 29 tools are callable directly (no curl/JSON-RPC):

```bash
# Non-interactive (no auth, enable all tools):
printf 'n\nY\n' | hermes mcp add sage --url "https://mcp.sagecontinuum.org/mcp"

# Verify:
hermes mcp list
```

After adding, start a new session. Tools appear as `mcp_sage_*` (e.g. `mcp_sage_list_available_nodes`, `mcp_sage_find_plugins_for_task`). No auth needed for read-only operations (data queries, node listing, plugin search, docs). Job submission tools (`submit_sage_job`, `submit_plugin_job`) require a Bearer token configured via portal.

## Working with This Project

- Project notes live at `~/AI-projects/Sage-agents/sage-agents.md` (15K+ bytes of detailed research)
- Pete Beckman leads the Sage project (Northwestern University, pete.beckman@northwestern.edu — no longer at ANL). He has deep domain expertise and works on ML plugins for Thor nodes (128GB unified memory, aarch64, GB10 Blackwell). Use his Northwestern email in all sage.yaml `authors` fields and ecr-meta credits.
- DGX Spark and Thor nodes share the same 128GB unified memory architecture — model sizing for one applies to the other
- When developing plugins, test with `virtual-waggle` (simulated node environment)
- Data API is public and unauthenticated — good for quick verification
- Node IDs look like W030, W09E, W0A0 (hex-style short codes called VSN)

## Pitfalls

- **MCP add is interactive**: `hermes mcp add sage --url <url>` prompts for auth token and tool filtering. Pipe `printf 'n\nY\n'` for no-auth, enable-all-tools. Must start new session after adding.
- **Naming rules are strict**: repo names = lowercase alphanumeric + hyphens only (NO underscores); job names = lowercase letters, numbers, hyphens only (no underscores, uppercase, dots); plugin names in sage.yaml can use underscores
- **Version immutability**: cannot resubmit same version to ECR — bump version every time
- **Bulk version bumps in monorepos**: when bumping versions (e.g. `0.1.0` → `0.2.0`) across sage.yaml, job YAMLs, Dockerfiles, and docs, skip generic tutorial/example files that use the old version as a hypothetical placeholder (e.g. `docs/sage-runtime-packaging-tutorial.md` using `my-plugin:0.1.0` as a generic example). Use `replace_all=True` per-file rather than a blind global sed to avoid corrupting unrelated examples.
- Manifests endpoint requires trailing slash (`/manifests/` not `/manifests`)
- Data API uses NDJSON (newline-delimited JSON), not standard JSON array
- Portal can be slow/timeout — prefer API endpoints for programmatic access. Portal rebuilds DB on Sundays.
- sage-data-client returns pandas DataFrames — ensure pandas is installed
- Plugin base images are multi-arch but verify ARM64 vs x86 for target node
- **Protected data access requires `-L` (follow redirects)**: `curl -L -u <username>:<portal-access-token> -o output.jpg <url>` — token from portal account page. The Sage storage API at `storage.sagecontinuum.org` returns a **302 redirect** to the actual backend (`nrdstor.nationalresearchplatform.org`) with a signed JWT in the query string. Without `-L`, curl gets an empty 302 response and writes a 0-byte file. Always use `-L` when downloading from Sage storage. In Python, use `subprocess.run(["curl", "-s", "-f", "-L", "-u", ...])` rather than urllib — the NRP backend may do a double redirect that urllib can't follow.
- **Sage portal username for storage auth**: Use the portal username (e.g. "beckman"), not GitHub username. Token from `portal.sagecontinuum.org/account/access`. Format: `curl -u <portal-username>:<access-token>`.
- Dockerfile MUST have proper ENTRYPOINT or pluginctl will fail
- **pywaggle meta values MUST be strings**: `plugin.publish()` calls `valid_meta()` which enforces `isinstance(v, str)` for every meta dict value. Passing int/float meta values (e.g. `{"confidence": 0.95}`) silently raises ValueError. Always wrap: `meta={"confidence": str(score), "count": str(n)}`
- **pywaggle topic names MUST be `[a-z0-9_]` joined by dots**: YOLO COCO classes include multi-word names with spaces (`dining table`, `traffic light`, `potted plant`, `hot dog`, `fire hydrant`, `stop sign`, `tennis racket`, `cell phone`, `teddy bear`, etc.). Using these directly in `plugin.publish(f"env.count.{cls_name}", ...)` raises `ValueError: publish name invalid`. Sanitize before publishing: `safe_name = cls_name.replace(" ", "_").replace("-", "_")`. This bug is insidious — the per-class publish calls before the offending class succeed, but `env.count.total` and `upload_file()` never run for that image, making it appear to have zero detections.
- **`test_harness.py` is a library, not a test**: When writing test discovery scripts (like `run-all-tests.sh`), exclude `test_harness.py` from the glob `test_*.py`. It's a shared utility module copied into each plugin's `tests/` directory — running it directly fails or produces misleading results. Pattern: `find . -name "test_*_unit.py"` (not `test_*.py`).
- **pytest namespace collision across plugins**: Multiple plugins each have `tests/test_harness.py`. pytest's default import mode (`prepend`) treats them as the same module — the second import silently gets the first plugin's harness, causing mysterious failures. Fix: add `pyproject.toml` at repo root with `[tool.pytest.ini_options] import_mode = "importlib"`. Do NOT try adding `__init__.py` to test dirs — it turns them into packages and breaks relative imports (`ModuleNotFoundError` on `test_harness`).
- **Don't import plugin app.py in unit tests if it has torch/CUDA deps**: mocking `torch` via `sys.modules` poisons `numpy` (reimport fails with "cannot load module more than once"). Instead, test publish logic directly by calling pywaggle APIs with canned detection results. See `references/testing-patterns.md`
- **BioCLIP classifies every frame — always produces a prediction**: Unlike YOLO (which only reports when it detects something), BioCLIP's `TreeOfLifeClassifier.predict()` always returns ranked predictions with scores, even for empty scenes. An IR nighttime image of a hummingbird feeder (no bird present) returns "Archilochus colubris" at ~19% — it learned the feeder shape association. Use `--min-confidence 0.5` (or higher) to gate publishing so it only reports when genuinely confident. Without this, the plugin publishes species predictions every cycle regardless of content. For detection-triggered species ID, consider using YOLO as the trigger (detects "bird") and BioCLIP as enrichment (identifies species) — correlate by timestamp in a cloud-side watcher.
- **Low-confidence images: upload only in test mode**: For classification plugins (BioCLIP), only upload annotated images when confidence exceeds threshold in production (camera/snapshot-url mode). In test mode (--image-dir), upload all images with annotations so every result can be reviewed. This avoids flooding NRP storage with one image per cycle in production while still getting full test coverage. Annotation pattern: use `cv2.putText` with orange BGR `(0, 165, 255)` on a black background rectangle. Above threshold: show top-5 predictions in top-left corner. Below threshold: show "No confident species prediction (best: X%)" at bottom. Scale font to image size: `scale = max(0.5, min(w, h) / 1000.0)`.
- **Prefer pybioclip over raw open_clip for BioCLIP plugins**: `pybioclip>=2.1.5` provides `TreeOfLifeClassifier` that handles model loading, taxonomy, and text embeddings automatically. Returns list-of-dicts with rank keys (`kingdom`...`species`) + `score`. Much cleaner than manual open_clip + pre-computed embeddings. The `model_str` parameter accepts any HuggingFace model string (`hf-hub:imageomics/bioclip-2`, `hf-hub:imageomics/bioclip-2.5-vith14`, etc.) — but BioCLIP 2.5 requires a monkey-patch until pybioclip adds native support (see pitfall below). Text embeddings for 2.5 exist at `https://huggingface.co/datasets/imageomics/TreeOfLife-200M/tree/main/embeddings` (3 GB npy + 80 MB json). See `references/ml-plugin-patterns.md`.
- **Production vs test image upload behavior**: Classification plugins (BioCLIP) should only upload annotated images when confidence exceeds `--min-confidence` threshold in production mode (camera/snapshot-url). In test mode (`--image-dir`), upload ALL images with annotations so every result can be reviewed. This matches YOLO's behavior: YOLO only saves images when it detects objects; BioCLIP should only save when it has a confident species prediction. The guard: `if using_image_dir:` around the below-threshold upload block.
- **BioCLIP model upgrade path (2 → 2.5 → future)**: Upgrading BioCLIP versions requires: (1) change `--model` default in app.py, (2) update the `TreeOfLifeClassifier(model_str=...)` line in Dockerfile's model-bake step, (3) update `patch_pybioclip.py` if the new model isn't in pybioclip's `TOL_MODELS`, (4) bump sage.yaml version. Key differences: BioCLIP 2 uses ViT-L/14 (~430M params, ~2.5GB VRAM, memory=8Gi/16Gi), BioCLIP 2.5 uses ViT-H/14 (~1B+ params, ~5-7GB VRAM, memory=16Gi/32Gi, +5.7% accuracy). Both use 224x224 input. The model string format is `hf-hub:imageomics/<model-name>`. Always tag the repo before upgrading (`git tag v<old>`) so you can revert. **Tested**: BioCLIP 2.5 detects hummingbirds at 99.95-100% confidence vs 97% for BioCLIP 2. Confidence higher on 32/34 test images.
    **CRITICAL: pybioclip `TOL_MODELS` whitelist blocks new models.** pybioclip 2.1.5 hardcodes `TOL_MODELS` in `bioclip/_constants.py` (NOT `predict.py`). Format: `TOL_MODELS = {BIOCLIP_V1_MODEL_STR: TOL10M_HF_DATAFILE_REPO, BIOCLIP_V2_MODEL_STR: TOL200M_HF_DATAFILE_REPO}`. `TreeOfLifeClassifier` raises `ValueError: TreeOfLife predictions are only supported for...` for any model not in the dict. Additionally, `get_txt_emb()` and `get_txt_names()` in `predict.py` hardcode `embeddings/txt_emb_species.{npy,json}` filenames, but newer models use model-specific filenames (e.g. `txt_emb_bioclip-2.5-vith14.{npy,json}` in the `imageomics/TreeOfLife-200M` HuggingFace **dataset** repo under `embeddings/`). The embeddings ARE available — check `https://huggingface.co/api/datasets/imageomics/TreeOfLife-200M/tree/main/embeddings` for the full list. `predict.py` imports `TOL_MODELS` via `from ._constants import (` on one line, then `    HF_DATAFILE_REPO_TYPE, BIOCLIP_MODEL_STR, TOL_MODELS,` on the next (indented continuation). **Fix: use a separate Python patch script** (not inline RUN — multi-line Python in Dockerfile breaks the parser with `unknown instruction` errors). The script patches two files: (1) `bioclip/_constants.py` — add the new model to `TOL_MODELS` dict and add a `TOL_EMB_FILES` dict mapping model strings to `(npy, json)` filename tuples; (2) `bioclip/predict.py` — add `TOL_EMB_FILES` to the import line and override the hardcoded `txt_emb_species.{npy,json}` in `get_txt_emb()` / `get_txt_names()` with lookups from `TOL_EMB_FILES`. Dockerfile pattern: `COPY patch_pybioclip.py /tmp/patch_pybioclip.py` then `RUN python3 /tmp/patch_pybioclip.py && rm /tmp/patch_pybioclip.py`. **String matching pitfalls** (each caused a build failure): (1) `TOL_MODELS` is in `_constants.py` (NOT `predict.py`) and uses variable references (`BIOCLIP_V2_MODEL_STR`), not string literals — matching `'hf-hub:imageomics/bioclip-2'` fails; (2) the import in `predict.py` uses relative form `from ._constants import (` — match the exact indented continuation line `    HF_DATAFILE_REPO_TYPE, BIOCLIP_MODEL_STR, TOL_MODELS,`, not the `from` line itself; (3) always use `docker run --entrypoint python3 <image> -c "import bioclip._constants; ..."` to inspect the actual installed source before writing the patch script. See the sage-bioclip repo's `patch_pybioclip.py` for the complete working patch. This is fragile — when pybioclip upstream adds support, remove the patch.
- **vLLM model download can be huge**: Qwen3-VL-32B-Instruct is ~67GB. Budget 10-15 min for first download. Use `--trust-remote-code` for Qwen models. Use non-default port (e.g. 8199) to avoid conflicts
- **vLLM 0.23.0 CLI breaking change**: `--disable-log-requests` was removed; use `--no-enable-log-requests`. The old flag causes the vLLM subprocess to exit silently (unrecognized argument), leaving a `<defunct>` zombie process. Symptom: server PID shows `<defunct>` in `ps`, port never starts listening, no error in parent process. Always verify vLLM server is actually running after Popen launch (check `ps` for `<defunct>`, check port with `ss -tlnp`). When upgrading vLLM, run `--help` to verify flag names haven't changed.
- **Redirect vLLM server output to a log file**: When launching vLLM as a subprocess, send stdout/stderr to DEVNULL (or a log file) instead of `subprocess.PIPE`. PIPE can cause deadlocks on large output and makes debugging harder. Log file lets you inspect server startup errors post-mortem. Both stdout and stderr should go to DEVNULL — routing only one to PIPE while the other goes to DEVNULL is still a deadlock risk if the PIPE buffer fills.
- **`--continuous N` breaks `--image-dir` batch mode**: The common main-loop pattern `if args.continuous != "Y": break` fires after the FIRST image even in `--image-dir` mode, so only one file gets processed. The fix: `if args.continuous != "Y" and not using_image_dir: break` — let the directory iterator's `StopIteration` handle the exit. This bug is silent and hard to spot because the plugin exits cleanly with valid output — it just only processed one image instead of all of them. Always verify the NDJSON record count matches the image count after batch runs.
- **Always test `--image-dir` and `--stream` modes separately**: Plugin app.py files typically have multiple input modes (single image, directory glob, camera stream). Code paths for `--image-dir` (using `os.listdir`, `os.path.join`) may reference `os` without importing it if the initial development only tested `--stream` mode. Always run all CLI modes during local testing to catch missing imports.
- **Reolink HTTP snapshot: always request low-res for inference**: The Reolink CGI API returns full 4K (3840x2160, ~445KB) by default. Append `&width=640&height=360` to the snapshot URL to get sub-stream resolution (~12KB). That's a 38x bandwidth reduction — critical for LTE-connected cameras. YOLO resizes to 640px anyway so full-res snapshots waste bandwidth with zero accuracy benefit.
- **Unified memory GPU fraction ≠ discrete GPU**: On 128GB unified memory nodes (DGX Spark, Thor, Grace Hopper), vLLM reports ~121 GiB total but the OS shares the pool. Effective usable fraction is ~0.55-0.60, not 0.80-0.90 as with discrete GPUs. Use `--gpu-memory-utilization 0.58` for 32B models. Both 0.80 and 0.85 OOM.
- **`--enforce-eager` required for large models on unified memory**: CUDA graph capture consumes ~5GB extra memory. For 32B+ models on 128GB unified memory, this causes OOM even at conservative GPU fractions. Add `--enforce-eager` to skip graph capture (~10-15% throughput cost, prevents OOM).
- **Never commit `.pt` / `.safetensors` model weights to git**: Model weight files (e.g. `yolo11x.pt`, 110MB) get auto-downloaded by libraries like ultralytics into the working directory. Add `*.pt *.pth *.bin *.safetensors` to `.gitignore`. Models are baked into Docker images at build time via Dockerfile `RUN curl` — they don't belong in the source repo.
- **Long tutorial/doc files can stall write_file**: When writing documentation files >~500 lines (like the runtime packaging tutorial), the tool stream can time out. Write in sections: create the file with the first 2-3 sections via write_file, then append remaining sections via patch (find last line of existing content, replace with that line + new content). Each write should be under ~150 lines.
- **Patching pip-installed packages in Dockerfile**: When monkey-patching a pip-installed library (e.g. pybioclip), the source files are NOT where you'd expect from an editable install. Use `pathlib.Path(module.__file__)` to find the actual installed location (e.g. `/usr/local/lib/python3.12/dist-packages/bioclip/predict.py`). Always read the installed source to get exact string matches — don't assume formatting from GitHub. Common traps: (1) dict definitions may use variable references not string literals; (2) imports may use relative form (`from ._constants import`) with specific indentation on continuation lines; (3) the code may be spread across multiple files (`_constants.py` vs `predict.py`). Use `assert old in src` before each replacement to fail fast on mismatches.
- **Multi-line Python in Dockerfile RUN breaks the parser**: `RUN python3 -c "import foo\\nbar()"` with actual newlines causes `unknown instruction: IMPORT` errors — Docker interprets each line as a Dockerfile instruction. **Always use a separate `.py` script file**: `COPY script.py /tmp/` then `RUN python3 /tmp/script.py && rm /tmp/script.py`. Single-line Python with `\` continuations works only for trivial 1-2 line scripts. This is the pattern used for `patch_pybioclip.py`.
- **"Multi-stage build" terminology trap in docs**: Dockerfiles with one `FROM` are single-stage builds, even if they have multiple `RUN` steps (download model, warmup, install deps). "Multi-stage" specifically means multiple `FROM` statements. Overview.md docs have been corrected but watch for this when writing new plugin documentation. Multiple `RUN` layers ≠ multi-stage build.
- **ALL documentation surfaces must be updated with every code change**: When changing CLI args, audio sources, model features, Waggle topics, or behavior, update ALL four documentation files in the same commit: (1) `README.md` (GitHub landing page), (2) `ecr-meta/README.md` (ECR portal usage), (3) `ecr-meta/ecr-science-description.md` (ECR portal science tab), (4) `sage.yaml` inputs section. Also update `jobs/*.yaml` if args changed. NEVER commit code changes without proactively checking all four doc files — Pete considers this a serious oversight and will call it out. After every code change, check all four files plus jobs/*.yaml without being asked. The rule: if you touch app.py's argparse or behavior, the same commit (or at minimum the same PR) must touch all doc surfaces. Verify with `git diff --stat` before committing — if only `.py` files changed but args were added/modified, the commit is incomplete. This applies to ALL plugin repos (sage-yolo, sage-bioclip, birdnet, etc.) — it's a universal standard, not a per-project preference.
- **overview.md drifts from code quickly**: Line counts, argument counts, meta field lists, Dockerfile snippet ordering, and flag names in overview.md go stale as app.py evolves. After any code change, audit the overview for: (1) line ranges/counts, (2) argument/input counts, (3) meta={} field examples matching actual publish() calls, (4) Dockerfile snippets matching actual Dockerfile layer order, (5) CLI flag names matching argparse definitions, (6) test file references (deleted tests still mentioned), (7) sage.yaml `testing.command` pointing to current test files. Use delegate_task to parallelize auditing all plugins' overview.md + sage.yaml files against code simultaneously.
- **Documentation consistency across plugins**: All plugin config tables should use the same format: `Flag | Type | Default | Description`. Test runner CLI options also get their own table. When adding argparse flags from a third-party library, the help text should include a direct URL to the upstream docs. sage.yaml `inputs:` must list every argparse flag. Job YAML examples should show all commonly-used flags.
- **opencv-python-headless for edge plugins**: Always use `opencv-python-headless` in requirements.txt for edge plugins (no GUI on nodes). If overview.md warns about switching *to* headless, that warning is probably backwards — check requirements.txt first.
- **macOS `._` resource fork files break cv2.imread**: When test images are copied via macOS Finder or Samba, `._*` resource fork files appear alongside each image. These have valid image extensions (e.g. `._test-image001.jpg`) but are not real images — `cv2.imread()` returns `None`, causing assertion failures in tests. Always filter with `not name.startswith(".")` when globbing test image directories — in EVERY place that iterates images: `app.py:iter_image_dir()`, `test_harness.py:get_test_images()`, local test runner `count_images()`, and integration test image lists. Add `._*` to `.gitignore` to prevent committing them. The files keep coming back via Samba — add `veto files = /._*/.DS_Store/` and `delete veto files = yes` to smb.conf `[global]` to block creation server-side.
- **Samba over Tailscale for remote file browsing**: To mount a node's filesystem on a Mac (Finder Cmd+K), install Samba on the node. `bind interfaces only = yes` with `interfaces = tailscale0` does NOT work — Tailscale's point-to-point interface lacks broadcast capability and Samba silently falls back to loopback only. Fix: remove `bind interfaces only`, use `hosts allow = 100.64.0.0/10 127.0.0.1` + `hosts deny = 0.0.0.0/0` under `[global]` instead. This restricts access to Tailscale CGNAT range without needing interface binding. To prevent macOS from creating `._*` resource forks and `.DS_Store` files on the server, add `veto files = /._*/.DS_Store/` and `delete veto files = yes` under `[global]`. See `references/direct-node-testing.md`.
- **Bare file paths fail in Docker with Camera()**: `Camera("/images/test.jpg")` inside a Docker container triggers pywaggle's named-stream lookup (no `://` scheme) → `FileNotFoundError: /run/waggle/data-config.json`. Fix: use `file://` prefix: `Camera("file:///images/test.jpg")`. On the host (not in Docker), bare paths work because `resolve_device_from_data_config` falls through to `resolve_device_from_path`. This only bites you in Docker where `/run/waggle/data-config.json` doesn't exist.
- **Email cron job must NEVER auto-reply**: The email checking cron job must be read-only — list inbox, read unread messages, mark as seen, summarize. NEVER compose or send replies from a cron job. Each cron run is a fresh session with no memory of previous runs, so it cannot track "I already replied to this." Without state tracking, auto-reply + failed mark-as-read = spam loop (28 duplicate emails sent in one incident). Replies should only happen when explicitly requested in a live chat session. The correct himalaya flag syntax is `himalaya flag add -a sage <ID> seen` (positional arg, NOT `--flag seen`).
- **Tmux session transcripts**: Save to the dedicated `~/AI-projects/tmux-logs/` directory (NOT the bare `~/AI-projects/` root, NOT inside a project repo). Filename convention: `hermes-yolo-session-YYYY-MM-DD-partN-ansi.txt` — `hermes-yolo-session-` prefix, ISO date, then `partN` (start a fresh `part1` for each new date; bump the part number for additional captures the same day as the tmux history buffer rolls over). Capture full scrollback WITH ANSI color codes: `cd ~/AI-projects/tmux-logs && tmux capture-pane -t <session>:<win>.<pane> -e -p -S - > hermes-yolo-session-YYYY-MM-DD-partN-ansi.txt`. The `-e` flag preserves ANSI SGR codes (verify with `grep -c $'\033' <file>`); `-S -` grabs the entire history buffer (find the pane via `tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} hist=#{history_size}'`). Caveat: tmux only retains what's within its `history-limit`; anything scrolled off before capture is unrecoverable — that's why old sessions were split into part1–7.
- **Upload agent clears files almost instantly**: The `wes-upload-agent` pod scans `/media/plugin-data/uploads/<job>/<plugin>/<version>/` on the host, rsyncs to `beehive-uploads.sagecontinuum.org`, and deletes immediately. There is no practical window to intercept files on-node before they're cleaned up. Don't try to race it; use the Sage data API to find upload URLs instead.
- **NRP storage (nrdstor.nationalresearchplatform.org) can lag or break globally**: Beehive receives uploads fine but the Beehive-to-NRP sync can fail globally. Symptoms: data API shows upload records with valid URLs, but `curl -L -u user:token <url>` returns 404 ("Unable to open ... no such file or directory") from the NRP backend. Old files may still work while new ones 404. Debug: (1) check `wes-upload-agent` logs on node — if it shows "uploaded all files found" with no errors, the node side is fine; (2) try downloading from a different node's recent uploads — if those also 404, it's a global NRP issue; (3) `dig nrdstor.nationalresearchplatform.org` to see which replica you're hitting. This is a Sage infrastructure issue — escalate to the cyberinfrastructure team.
- **pywaggle upload_file may move (not copy) the temp file**: After `plugin.upload_file(tmp_path, ...)`, the file at `tmp_path` may no longer exist — pywaggle moves it to the upload directory. Guard any cleanup: `if os.path.exists(tmp_path): os.unlink(tmp_path)`.
- **NRP storage has propagation delays or outages**: Files uploaded from edge nodes may 404 on NRP storage even though the Sage data API shows the upload record. This can be propagation delay (minutes) or a Beehive-to-NRP sync outage (hours+, affects all nodes globally). To diagnose: (1) check if old uploads still work (propagation vs outage), (2) try uploads from other nodes (node-specific vs global), (3) check the upload agent on the node: `sudo kubectl logs wes-upload-agent-<id> --tail=30` — if it shows "uploading/cleaning/done" cycles with no errors, the node side is fine and the problem is downstream. The upload agent uses rsync to `beehive-uploads.sagecontinuum.org`. Upload files live briefly at `hostPath: /media/plugin-data/uploads/<job>/<plugin>/<version>/` before being rsynced and deleted — the window is too short to intercept. Alternative for image delivery when NRP is down: SSH to the node and grab a fresh camera snapshot directly (`curl` the Reolink HTTP snapshot URL from the host).
- **Sage portal username for storage auth**: Use the portal username (e.g. "beckman"), not GitHub username. Token from `portal.sagecontinuum.org/account/access`. Format: `curl -u <portal-username>:<access-token>`.
- **`clean.sh` for pre-transfer cleanup**: The repo includes a `clean.sh` script that removes test outputs, downloaded model weights (.pt/.pth/.bin/.safetensors), `__pycache__`, macOS junk (`._*`, `.DS_Store`), and `.pytest_cache`. Run `./clean.sh` for a dry run, `./clean.sh --force` to delete. Always run before `git add`, rsync to another machine, or archiving.
- **Slack incoming webhooks cannot upload files**: Webhooks accept JSON text/blocks only. To post images to Slack, use a Slack Bot Token with `slack_sdk` (`pip install slack_sdk`) and `files_upload_v2()` — this is the current API (old `files.upload` retired March 2025). Requires creating a Slack app with `files:write` + `chat:write` scopes, installing it, and inviting the bot to the channel. Store the bot token and channel ID in `secrets/bot-secrets` (shell export format, gitignored, `chmod 600`). See `references/cloud-trigger-notifications.md` for the full setup and working code.
- **Sage containers are network-restricted but host processes may not be**: Containers on edge nodes cannot reach external services (Slack, email APIs, etc.). Host processes via SSH on some nodes (e.g. Thor H00F) CAN reach the internet — verified with `curl https://hooks.slack.com/` returning 302. The recommended pattern is still a cloud-side watcher, not a host-side process. See `references/cloud-trigger-notifications.md`.
- **Docker test output lands in project root `output/`**: When running `docker run` with `-e PYWAGGLE_LOG_DIR=/output -v $(pwd)/output/yolo-docker-test:/output`, output goes to `<repo>/output/` not `<repo>/tests/output/`. Make sure `.gitignore` includes top-level `output/` in addition to `tests/output/` and `plugins/*/tests/output/`.
- **NVIDIA Thor nodes: torch CUDA availability**: On Sage Thor nodes (NVIDIA Thor GPU, driver 580.00, CUDA 13.0), `torch.cuda.is_available()` returns False even though `torch.version.cuda` reports `13.0`, `_is_compiled()` is True, and `device_count()` returns 1. Root cause: `/dev/nvmap` is `cr--r----- root:video` — the Tegra memory manager requires `video` group. `torch.cuda.init()` → `NvRmMemInitNvmap Permission denied` → `RuntimeError: No CUDA GPUs are available`. Note: `/dev/nvidia*` are `rw-rw-rw-` — the blocker is specifically `/dev/nvmap`. Debug: (1) `ls -la /dev/nvmap`, (2) `groups`, (3) `getent group video`. The `NvRmMemInit` stderr messages look like noise but ARE the failure signal. **Sage docs warn: "Do not run any app or install packages directly on the node."** Use `sudo pluginctl build/deploy` which gives containers proper GPU access. Direct `python3 app.py` requires `video` group (`sudo usermod -aG video <user>` + re-login).
- **pluginctl requires sudo (ALL commands including logs)**: k3s kubeconfig at `/etc/rancher/k3s/k3s.yaml` is root-only. ALL pluginctl commands require sudo on Thor: `sudo pluginctl build .`, `sudo pluginctl deploy`, `sudo pluginctl ps`, `sudo pluginctl logs`, `sudo pluginctl rm`. Without sudo, commands fail with permission errors (e.g. `pods "name" is forbidden`). Docker on Thor also requires sudo.
- **pluginctl deploy "Forbidden: pod updates may not change fields other than image"**: When a plugin pod with the same `-n <name>` already exists, `pluginctl deploy` tries to *patch* the running pod in place. Kubernetes only permits changing a handful of fields on a running pod (`spec.containers[*].image`, `initContainers[*].image`, `activeDeadlineSeconds`, `tolerations`, `terminationGracePeriodSeconds`). Any other change (volumes, the `kube-api-access-*` mount, args, env) is rejected with `Error: Pod "<name>" is invalid: spec: Forbidden: pod updates may not change fields other than ...` plus a diff showing the removed/changed fields. **Fix: delete the existing pod first, then deploy fresh:** `sudo pluginctl rm <name>` → verify gone (`sudo pluginctl ps` or `sudo kubectl get pods | grep <name>`) → redeploy. If the pod is stuck `Terminating`, force-delete: `sudo kubectl delete pod <name> --grace-period=0 --force`. This bites whenever you redeploy with changed args/camera URL — the args change is exactly the kind of non-image field k8s won't patch.
- **pluginctl deploy requires --resource for GPU plugins**: The default k3s memory limits are too low for YOLO11x and similar large models. Without `--resource 'memory=8Gi,limit.memory=16Gi'`, the pod gets OOMKilled (exit code 137). The resource flag syntax uses bare k8s names (`memory=8Gi`), NOT `resource.memory=8Gi` (that's for selectors). Check OOMKilled with: `sudo kubectl get pod <name> -o jsonpath='{.status.containerStatuses[0].state}'`. **Model-specific resource requirements**: YOLO11x needs `memory=8Gi,limit.memory=16Gi`. BioCLIP 2 (ViT-L/14) needs `memory=8Gi,limit.memory=16Gi`. BioCLIP 2.5 Huge (ViT-H/14) needs `memory=16Gi,limit.memory=32Gi` — OOMs at 8Gi/16Gi during text embeddings loading (~3 GB `.npy` file + ~4-5 GB model weights). Always check `sudo kubectl get pods | grep <name>` for `OOMKilled` status after first deploy of a new model version.
- **SSH ControlPersist + ProxyJump + passphrase key = frequent disconnects**: When SSH config uses `ControlPersist 10m` on the jump host (sage-vpn) and a passphrase-protected `IdentityFile`, connections through `ProxyJump` expire after 10 minutes of idle. The next SSH command needs the agent to provide the key again, but the agent may have been restarted or the `SSH_AUTH_SOCK` changed. Symptoms: "Permission denied" errors on SSH commands that worked minutes ago, especially during long background operations (Docker builds, k3s imports). **Root cause**: the `*.sage` host block uses `ProxyJump sage-vpn` but has no `IdentityFile` of its own — it relies entirely on the agent. When the control master expires and must reconnect, both the jump and the target need the key. **Fix**: add `IdentityFile ~/.ssh/sage_key` and `IdentitiesOnly yes` to the `*.sage` block so SSH can find the key without the agent. Keep `User root` as default (override with `beckman@` on command line as needed). Save backup: `cp ~/.ssh/config ~/.ssh/config.old`. For long operations (docker build, k3s import), always use `nohup` on Thor so the work survives SSH disconnections:
    ```bash
    ssh beckman@node-H00F.sage "cd /tmp/sage-bioclip && nohup sudo docker build -t bioclip:0.2.0 . > /tmp/build.log 2>&1 &"
    # Check progress:
    ssh beckman@node-H00F.sage "tail -5 /tmp/build.log"
    ```
    Similarly for k3s import: `nohup bash -c 'sudo docker save IMAGE | sudo k3s ctr images import - > /tmp/import.log 2>&1 && echo DONE >> /tmp/import.log' &`
- **ECR multi-arch arm64 build fails with NVIDIA base images (QEMU)**: ECR Jenkins builds both `linux/amd64` and `linux/arm64` from sage.yaml's `source.architectures`. The arm64 build uses QEMU emulation on an amd64 host, which crashes (`qemu: uncaught target signal 6 (Aborted) - core dumped`) when the NVIDIA PyTorch base image tries to `import torch` during any `RUN` step. This affects ALL plugins using `nvcr.io/nvidia/pytorch:*` as base. The amd64 build succeeds fine. **Confirmed**: sage-bioclip v0.3.0 failed on ECR with this exact error at the pip constraints `RUN` step (first step that imports torch). **Fix options**: (1) Remove `linux/arm64` from sage.yaml architectures — ECR builds amd64 only, build arm64 locally on Thor/DGX Spark; (2) Ask ECR team for native arm64 builder (no QEMU); (3) Use a lighter base image for arm64 that doesn't require GPU at build time. Until fixed upstream, arm64 images must be built locally and transferred via `docker save | k3s ctr images import`.
- **ECR is NOT a Docker registry you push to**: Sage ECR pulls source from your public GitHub repo and builds the image. You do NOT run `docker login`, `docker tag`, or `docker push` against `registry.sagecontinuum.org`. The workflow is: push code to GitHub → register on portal.sagecontinuum.org → ECR builds → get registry tag from "Tags" tab. For pre-ECR testing on Thor nodes, use `docker save | gzip` + `scp` + `sudo k3s ctr images import`. **`sesctl submit` validates the image against the ECR app catalog, but `pluginctl deploy` does NOT** — a pluginctl-runnable image can still fail `sesctl submit` with `400 ... does not exist in ECR` if it was never built in the portal pipeline. See `references/docker-build-deploy.md` and `references/sesctl-ecr-validation.md`.
- **Thor/Sage nodes have no outbound internet from containers**: Most Sage edge nodes are firewalled — `docker build` with `pip install` fails with DNS resolution errors. Build Docker images on a machine WITH internet (DGX Spark, CI server), then transfer or publish to ECR. **Exception**: some Thor nodes DO have Docker installed and outbound internet access. On those nodes, clone the repo and build directly (`git clone` + `sudo docker build`) for faster iteration — skip the save/scp/load dance. Check with `curl -s https://pypi.org > /dev/null` and `sudo docker --version`. All Docker commands on Thor require `sudo`. See `references/docker-build-deploy.md` for both workflows.
- **NVIDIA Container Toolkit: installed ≠ configured**: On dev machines (DGX Spark, personal workstations), the `nvidia-container-toolkit` package may be installed but Docker doesn't know about the `nvidia` runtime until configured. `docker run --runtime=nvidia` fails with `unknown or invalid runtime name: nvidia`. Fix (one-time per machine): `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`. Verify: `docker info | grep -i runtime` should show `nvidia`. Thor nodes have this pre-configured by Sage. See `references/docker-build-deploy.md`.
- **`--runtime=nvidia` not `--gpus all` for portable Docker commands**: Thor nodes use an older NVIDIA Container Runtime Hook that does NOT support `--gpus all` — it errors with `invoking the NVIDIA Container Runtime Hook directly is not supported. Please use the NVIDIA Container Runtime (e.g. specify the --runtime=nvidia flag) instead`. DGX Spark supports both flags. Always use `--runtime=nvidia` in documentation and scripts so commands work on both DGX Spark and Thor without modification. `--gpus all` is a newer nvidia-container-toolkit feature; `--runtime=nvidia` is the older/universal path that both setups support.
- **OpenCV/numpy conflict in NVIDIA base images**: The NVIDIA base image ships its own opencv compiled against a specific numpy. Installing ultralytics/pybioclip/vllm can pull a different numpy (1.x→2.x or version mismatch), breaking cv2 with `ImportError: numpy.core.multiarray failed to import`. Fix in Dockerfile (works for both numpy 1.x and 2.x bases): `pip uninstall -y opencv-python opencv-python-headless 2>/dev/null; rm -rf /usr/local/lib/python3.*/dist-packages/cv2* && pip install --no-cache-dir opencv-python-headless>=4.8.0`. Three things that DON'T work: (1) `--force-reinstall` alone — leaves stale .so files. (2) `pip uninstall` alone — also leaves stale files. (3) Just adding opencv-python-headless to requirements.txt — the base image's GUI opencv takes priority. The `rm -rf cv2*` with a python3.* glob (not hardcoded version) is essential. Use `python3` not `python` in ENTRYPOINT for Python 3.12+ base images.
- **pip install overwrites NVIDIA base image packages (CRITICAL)**: When `requirements.txt` lists `torch>=2.0.0`, `numpy>=1.24.0`, or `ultralytics` (which depends on all of them), pip replaces the base image's NVIDIA-compiled packages with generic PyPI versions. Three things MUST be frozen via pip constraints file: (1) **torch** — generic PyPI torch lacks Blackwell GPU kernels. Symptom: `RuntimeError: GET was unable to find an engine to execute this computation`. (2) **torchvision** — must match the NVIDIA torch build. (3) **numpy** — the base image ships numpy 1.26.4 and torch is compiled against numpy 1.x C ABI. If pip upgrades to numpy 2.x, `torch.from_numpy()` crashes with `RuntimeError: Numpy is not available`. Fix: remove `torch` and `numpy` from requirements.txt, then freeze all three in Dockerfile: `TORCH_VER=$(...) && TV_VER=$(...) && NP_VER=$(python3 -c "import numpy; print(numpy.__version__)") && printf "torch==${TORCH_VER}\ntorchvision==${TV_VER}\nnumpy==${NP_VER}\n" > /tmp/constraints.txt && pip install -c /tmp/constraints.txt -r requirements.txt`. Use the constraints file for ALL pip install commands in the Dockerfile. Note: the 25.08-py3 base image does NOT include torchaudio — don't try to freeze it. See `references/docker-build-deploy.md` for the complete Dockerfile pattern.
- **NVIDIA base image sm_xx / Blackwell compatibility**: DGX Spark (GB10) is sm_121 (CC 12.1). Thor (NVIDIA Thor / Jetson Thor) is sm_110 (CC 11.0). They are DIFFERENT compute capabilities despite both being "Blackwell". The 25.04-py3 image (CUDA 12.9) has cubins for `sm_80 sm_86 sm_90 sm_100 sm_120` — sm_110 is MISSING. On Thor: "NVIDIA Thor with CUDA capability sm_110 is not compatible" warning + CPU fallback. The 25.08-py3 image (CUDA 13.0) adds sm_110 support and covers BOTH machines. Use 25.08-py3 or newer for any deployment targeting Thor. Using `24.06-py3` on either machine silently falls back to CPU (sm_90 max). The symptom is deceptive — model loads fine, inference appears to hang (extremely slow, not a crash).
- **Ultralytics auto-downloads model weights when run outside Docker**: When running `python3 app.py` directly on a node (not in the Docker container), Ultralytics will download model weights (e.g. `yolo11x.pt`, ~130MB) to the current directory on first use. This is expected behavior for local testing — the Dockerfile bakes the model in so production containers never download. The download is a one-time cost; subsequent runs use the cached `.pt` file. `clean.sh --force` removes downloaded weights.
- **Reolink FLV/BCS auth: query params, NOT basic auth (ffmpeg exit 187)**: The Reolink BCS/FLV endpoint (`/flv?port=1935&app=bcs&stream=...`) does NOT accept HTTP basic auth in the URL (`http://user:pass@ip/...`). That form makes ffmpeg fail instantly with `Error opening input: End of file` / `exit 187`. Credentials MUST be passed as query parameters: `...&user=USER&password=PASS`. Confirmed working on a Reolink RLC-811A hummingcam (example host `CAMERA_IP:PORT`, user `CAMERA_USER`): `http://CAMERA_IP:PORT/flv?port=1935&app=bcs&stream=channel0_sub.bcs&user=CAMERA_USER&password=CAMERA_PASSWORD` (get the actual node camera IP/user/password from your instructor or the node owner — never hard-code a real credential in a skill or repo). **Shell escaping**: always wrap the whole `--camera` URL in SINGLE quotes when running `pluginctl deploy` by hand — a password containing `!` triggers bash history expansion under double quotes (and `&`/`?` need protection too). Note this is Reolink-specific: the Mobotix M16 MxPEG stream DOES use basic auth (`http://user:pass@ip/control/faststream.jpg?stream=MxPEG&needlength`) and that form is confirmed working. See `references/reolink-audio-capture.md`.
- **BirdNET does NOT normalize input amplitude — faint audio scores low**: Verified from BirdNET-Analyzer `audio.py` source: BirdNET preserves whatever amplitude is in the file (librosa loads to [-1,1] but does not loudness-normalize). The only amplitude-aware step, `smart_crop_signal`, uses RMS+peak energy to *rank* which 3-second segments to keep — it does not scale them. `sigmoid_sensitivity` is applied to the model's output logits (confidence shaping), NOT the waveform — it cannot recover missing SNR. So a quiet mic (audible-but-faint chirps) produces sub-threshold confidences no matter how many birds call. **Fix: pre-amplify the capture with a MEASURED FIXED gain** (`ffmpeg -af 'volume=NdB'`), not `dynaudnorm`/`loudnorm` (those compress dynamic range — they pull up background hiss in quiet passages, hurting SNR and often degrading BirdNET). Measure headroom first with `ffmpeg -af volumedetect -f null -` so you don't clip. There is no "double-leveling" risk since BirdNET does no input leveling. **Camera mic gain**: the Reolink RLC-811A exposes NO mic input gain — its web "Volume" setting is speaker output for two-way talk-back, not mic input (unlike the Mobotix M16 which has a real mic sensitivity control). Gain compensation must be done downstream in the ffmpeg capture. See `references/reolink-audio-capture.md`.
- **Expose ALL model parameters for audio plugins too**: The BirdNET V2.4 `model.predict()` API has parameters beyond the obvious (`top_k`, `min_confidence`): `bandpass_fmin` / `bandpass_fmax` (frequency filters — critical for bandwidth-limited camera mics, e.g. set `--bandpass-fmax 4000` for 8 KHz camera audio), `batch_size` (parallel chunk processing for long recordings), `half_precision`, `speed`. Always check `inspect.signature(model.predict)` when wrapping a new model library and expose the useful parameters as CLI flags. The user will ask "did you exploit the new model's features?"
- **Auto-detect node location from manifest**: Plugins should read `/etc/waggle/node-manifest-v2.json` for GPS coordinates when `--lat`/`--lon` are not specified. The manifest has `gps_lat` and `gps_lon` fields. Pattern: default `--lat`/`--lon` to -1, then in `main()` call `read_node_location()` which reads the manifest and returns `(lat, lon)` or `None`. This makes job YAMLs portable across nodes — no hard-coded coordinates. Combine with `--week auto` for fully automatic geo-filtering. Fail gracefully (log "No node manifest found — geo-filtering disabled") when the manifest is absent (dev machines, `--dry-run` testing). The manifest is at `/etc/waggle/node-manifest-v2.json` on both W nodes (Xavier NX) and Thor nodes.
- **Recommended M16 deployment command** (30s audio every 10 min, 0.60 threshold, auto geo-filtering):
  ```
  python3 app.py \
    --camera "http://admin:pass@CAMERA_IP/control/faststream.jpg?stream=MxPEG&needlength" \
    --duration 30 --min-confidence 0.60 --bandpass-fmax 4000
  ```
  Auto-location is UNRELIABLE on Sage: SES does not mount the manifest into pods and fixed nodes have no sys.gps.* publisher (confirmed H00F 2026), so pass `--lat`/`--lon` explicitly. See `references/node-gps-location-resolution.md`.
- **Credential hygiene in job YAMLs**: Never commit camera passwords or credentials to git. Use placeholders like `CAMERA_URL_HERE` in committed job YAMLs and pass actual credentials at deploy time via `pluginctl deploy -- --camera "http://user:pass@..."`. GitHub secret scanning will flag Basic Auth strings in URLs. If credentials are accidentally committed, use `git filter-repo --replace-text replacements.txt --force` to scrub all history, then `git push --force`. Install with `pip install git-filter-repo`.
- **pluginctl deploy with local Docker images on Thor**: After `sudo docker build -t name:tag .`, import into k3s with `sudo docker save name:tag | sudo k3s ctr images import -`, then deploy with `sudo pluginctl deploy -n job-name docker.io/library/name:tag -- --args`. The k3s ctr import output may show a space in the image name (display quirk, not an error). Verify with `sudo k3s ctr images list | grep name`. **CRITICAL**: if you rebuild the Docker image after adding new CLI args, you MUST reimport into k3s — the old k3s image won't have the new args and will fail with "unrecognized arguments".
- **Auto-detect node location for portable job configs**: When `--lat` and `--lon` are left at defaults (-1), the plugin reads `gps_lat`/`gps_lon` from `/etc/waggle/node-manifest-v2.json`. Combined with `--week auto`, this means the same job YAML deploys to any node without hard-coding location or season. Pattern: `read_node_location()` function with try/except around manifest read, returns `None` if no manifest (graceful fallback for testing on dev machines).
- **Xavier NX (W nodes) compatibility**: BirdNET V2.4 plugin runs on Xavier NX (Wild Sage W-series nodes). The `python:3.12-slim` base image works on arm64, TFLite inference is CPU-only (no GPU needed), ~1 GB RAM for model+runtime fits in 8 GB shared memory. W nodes with USB microphones (ETS ML1-WS IP54, 48 kHz) give full-bandwidth audio — much better than camera mics. Deployment is simplest: `python3 app.py --duration 30 --min-confidence 0.50` with no other flags needed. The 2.94 GB image size may be tight on nodes with limited storage.
- **k3s image import required for local testing**: Docker images built on-node are NOT automatically visible to k3s/pluginctl. After `docker build`, run `sudo docker save IMAGE:TAG | sudo k3s ctr images import -` before `sudo pluginctl deploy`. The import can take 30-60 seconds for a ~3 GB image. Verify with `sudo k3s ctr images list | grep IMAGE`.
- **k3s image update requires reimport**: After `docker build`, the k3s containerd cache still has the OLD image. Must run `sudo docker save IMAGE:TAG | sudo k3s ctr images import -` after every rebuild. Forgetting this causes "unrecognized arguments" errors when new CLI flags were added — the container runs the stale image.
- **0.60 confidence threshold for camera audio**: The M16's pcm_alaw 8 KHz (4 KHz Nyquist) produces a noise floor around 0.39 with false positives for geographically impossible species (Sunda Scops-Owl in Illinois). A 0.60 threshold eliminates all noise-floor detections while still catching real vocalizations. For USB mics (48 KHz, full bandwidth), 0.25 is fine — higher audio quality produces much stronger real detections.
- **Audio plugin tests must validate species + confidence, not just "runs"**: Pete requires tests that check (1) the top-1 species matches expected, and (2) confidence is within ±5% of reference values. The test must print a clear `✓ PASS` or `✗ FAIL` per file and a summary line (`✓ PASS — 9/9 tests passed`). Exit code 0/1 for CI. Pattern: run classifier with `--output CSV`, parse CSV in Python to find highest-confidence detection, compare species name (exact match) and confidence (±0.05 tolerance). Support both native and `--docker` modes. Generate reference values via `generate_manifest.py` which runs the classifier on all test audio and saves `manifest.json`. See the birdnet repo's `tests/run-tests.sh` for the working implementation. **Key**: the manifest captures the best confidence per species across all 3-second chunks (not per-chunk), so the test CSV parser must find the global max confidence row, not just the first row. **Docker CSV gotcha**: mktemp creates the file (empty), so app.py's `write_header = not os.path.exists(output_path)` skips the header. Either `rm -f` the temp file before running, or handle headerless CSV (detect first line, fall back to positional parsing: `row[3]` = scientific_name, `row[5]` = confidence). **Docker volume mount**: don't try `-v $CSV_TMP:/tmp/out.csv` (file-level bind mount) — write CSV inside the shared audio volume (`/data/__test_result_$$.csv`) and copy it out.
- **Xeno-Canto API v3 requires an API key**: The v2 API (`/api/2/recordings`) is gone — returns 404 with "Xeno-canto API v2 is no longer available." The v3 API (`/api/3/recordings`) requires a `key` parameter — returns 401 without it. Get an API key from `xeno-canto.org/account`. For test audio without an API key, use BirdNET's official test data repo (`birdnet-team/birdnet-test-data`) or Wikimedia Commons (rate-limited). Wikimedia search API: `commons.wikimedia.org/w/api.php?action=query&list=search&srsearch=<species>+bird+call&srnamespace=6` — returns File: titles for audio files (mp3/ogg). Get download URL via `action=query&titles=<title>&prop=imageinfo&iiprop=url`. Rate limit: ~15 requests before 429.
- **WAV→MP3 conversion can change top-1 species**: When converting test audio from WAV to MP3 (to reduce repo size), MP3 compression artifacts can shift confidence scores enough to flip which species ranks #1. Always re-baseline from the committed MP3 files, never from WAV originals. Use `generate_manifest.py` to rebuild `manifest.json` after conversion, then update test expectations in `run-tests.sh`. Check each file individually — some will be stable (e.g. single-species recordings at 99%+), others with close top-2 scores may flip.
- **Test audio must match deployment geography**: If the model covers North American species, test with North American bird recordings only. The BirdNET test data repo includes European species files (Red-backed Shrike, Eurasian Wryneck) — remove them from the test suite. This is a Pete requirement: "the audio samples should match the geographic capabilities of the model."
- **Unit tests vs real inference tests**: Mocked unit tests (fake detections, no GPU) provide limited value for GPU-dependent edge plugins — they only test pywaggle publish logic (topic names, meta types) which rarely changes. For Sage plugins, prefer a single real-inference test per plugin that runs app.py as a subprocess with `--image-dir` against committed test images. This exercises the full pipeline: model loading, inference, result aggregation, pywaggle publish, image annotation, and upload. If a unit test produces annotated images with fake bounding boxes, those images are actively misleading (identical boxes on every different input image). Remove fake-upload code from any remaining unit tests.
- **Meaningful upload filenames**: Use `os.path.splitext(source_name)[0]` + a suffix (`-annotated.jpg`, `-classified.jpg`, `-described.jpg`) instead of `tempfile.NamedTemporaryFile(suffix=".jpg")`. pywaggle prepends a timestamp to the filename passed to `upload_file()`, so the final name becomes `{timestamp}-{stem}-annotated.jpg` — human-readable instead of `{timestamp}-tmpjoktpbnb.jpg`.

## ECR Readiness Checklist

Before submitting a plugin, verify each item:

1. **Code**: `app.py --help` shows all flags with defaults and descriptions. Third-party library params exposed (not hardcoded). Class names sanitized for pywaggle topics.
2. **Dockerfile**: Base image supports target GPU architecture (25.08-py3 for both DGX Spark sm_121 + Thor sm_110, see NVIDIA base images table). Pip constraints file freezes torch+torchvision+numpy. Model weights baked in (no runtime download). Layer ordering correct (deps → opencv fix → model → app.py). Proper ENTRYPOINT (`python3` not `python` for 3.12+ images). OpenCV headless fix present (uninstall + rm + reinstall). Use `--no-cache` on first build to avoid stale layers.
3. **sage.yaml**: `source.url` and `homepage` point to the ACTUAL repo (not a placeholder like `waggle-sensor/plugin-<name>`). `inputs:` lists every argparse flag. `inputs` types are only `string` or `int` (no `bool` — use `string` for store_true flags). `testing.command` points to the current test file. Fields (`authors`, `collaborators`, `funding`, `license`, `keywords`) match `ecr-meta/` files.
4. **ecr-meta/**: All 6 files present — `ecr-icon.jpg` (512×512), `ecr-science-image.jpg` (1920×1080+), `ecr-science-description.md`, `ecr-credits-license.txt`, `ecr-project-keywords.txt`, `ecr-project-url.txt`.
5. **Tests**: Real GPU inference test passes. Test images committed (not gitignored).
6. **overview.md**: Config table matches argparse exactly. No stale test file references. File tree matches actual directory layout (no duplicates).
7. **Job YAML**: Model name matches Dockerfile baked model (or has a comment explaining the difference).

**Common ECR submission trap**: sage.yaml `source.url` and `homepage` often contain placeholder URLs from initial scaffolding (e.g. `github.com/waggle-sensor/plugin-<name>`) that point to repos that don't exist. `ecr-project-url.txt` sometimes points to `sagecontinuum.org` instead of the actual GitHub repo. Always verify these resolve and point to the real repo.

- **ECR requires one repo per plugin**: ECR pulls from a GitHub repo and expects `sage.yaml` + `Dockerfile` at the repo root. A monorepo with multiple plugins under `plugins/<name>/` does NOT work — ECR cannot target a subdirectory. Each plugin must be a separate public GitHub repo. When splitting: copy the plugin directory contents to the repo root (not into a subdirectory), add a `.gitignore` (test output, model weights, __pycache__, macOS junk), and update `source.url` in sage.yaml to point to the new repo.
- **Per-plugin repo structure must be consistent**: Every standalone plugin repo (sage-yolo, sage-bioclip, sage-vllm) should have the same structure: `app.py`, `Dockerfile`, `.dockerignore`, `.gitignore`, `requirements.txt`, `sage.yaml`, `overview.md`, `DOCKER-BUILD.md`, `THOR-TESTING.md`, `patch_pybioclip.py` (BioCLIP only), `ecr-meta/` (6 files), `jobs/` (job YAML), `tests/` (run-tests.sh, test script, test_harness.py, test-images/). Test output goes ONLY in `tests/output/` (gitignored). Ad-hoc Docker test runs should NOT create a top-level `output/` directory — use `tests/output/` or a temp directory outside the repo. The `tests/run-tests.sh` must work standalone (no monorepo venv path dependency). Tag releases before major upgrades (`git tag v<version>`).

**sage.yaml `inputs` types: only `string` and `int`**: The ECR spec does not support `type: "bool"` or `type: "float"`. Official Sage plugins (e.g. image-sampler) only use `string` and `int`. For argparse `store_true` flags (like `--half`, `--augment`, `--agnostic-nms`), use `type: "string"` and note in the description that it's a presence-only flag: `"Flag (no value needed). Include '--half' in args to enable."` For float parameters (like `--min-confidence 0.1`), use `type: "string"` and document the expected format in the description. In job YAML `args:`, these are just bare strings with no value: `- "--half"`.

**sage.yaml must stay consistent with ecr-meta files**: The `authors`, `collaborators`, `funding`, and `license` fields in sage.yaml should match `ecr-meta/ecr-credits-license.txt`. The `keywords` should match `ecr-meta/ecr-project-keywords.txt` (one keyword per line in the file, comma-separated in sage.yaml). The `homepage` should match `ecr-meta/ecr-project-url.txt`. When updating ecr-meta files, always update sage.yaml to match and vice versa.

## ECR Submission Structure (Proven)

Each plugin needs these files in `ecr-meta/` for ECR portal submission:

| File | Required | Content |
|------|----------|---------|
| `ecr-science-description.md` | Yes | Markdown narrative: what it does, why it matters, methodology |
| `ecr-credits-license.txt` | Yes | Authors, funding acknowledgment (NSF 1935984), license (BSD-3) |
| `ecr-project-keywords.txt` | Yes | One keyword per line, ontology-aligned where possible |
| `ecr-project-url.txt` | Yes | Single line: GitHub repo URL |
| `ecr-icon.jpg` | Yes | 512x512 plugin icon (see `references/ecr-image-generation.md`) |
| `ecr-science-image.jpg` | Yes | 1920x1080+ representative science image (see `references/ecr-image-generation.md`) |
| `README` | Helpful | Submission instructions for the developer |

sage.yaml enhanced format (proven working): add `description` field to each input, `resources` section (GPU, memory, architecture), `testing` section (local testing commands), `collaborators` list, `funding` acknowledgment.

Docker image naming: `registry.sagecontinuum.org/<user>/<plugin-name>:<version>`

**IMPORTANT**: You do NOT `docker push` to `registry.sagecontinuum.org`. ECR is a CI/CD system that pulls from your public GitHub repo and builds for you. Register at portal.sagecontinuum.org → My Apps → Create App → enter repo URL. See `references/docker-build-deploy.md` for the full workflow. **ECR BUILDER BROKEN (2026-07):** every `RUN` step fails at runc init (`can't mask dir /proc/acpi`, from the CVE-2025-31133 runc upgrade) — base-swap does NOT fix it, it's builder infra. Check `~/AI-projects/Infra-problems-to-fix.md` FIRST before diagnosing any Sage build/deploy failure. Workaround: podman on-node + `pluginctl` side-load. Full detail: `references/ecr-builder-proc-acpi-runc-bug.md`.

## See Also

- Monorepo archive: https://github.com/flint-pete/sage-edge-plugins
- Per-plugin repos (required for ECR submission; each has DOCKER-BUILD.md + THOR-TESTING.md): https://github.com/flint-pete/sage-yolo, sage-bioclip (v0.3.0 = BioCLIP 2.5 Huge, v0.2.1 = BioCLIP 2), sage-vllm, birdnet, image-sampler2. birdnet = BirdNET V2.4 audio classifier (`pip install birdnet`, TFLite CPU ARM64); sources `--input`/`--camera` URL/USB mic; Reolink FLV audio uses QUERY-PARAM auth not basic; auto-detects node location+week. Detail: references/audio-plugin-debugging-birdnet.md, references/birdnet-audio-debugging-and-geofilter.md, references/reolink-audio-capture.md.
- `references/architecture-detail.md` — full architecture notes
- `references/mcp-tools.md` — Sage MCP server tools catalog
- `references/rtsp-metadata-preservation.md` — WHY the RTSP H.264/H.265 stream carries NO per-frame JPEG metadata; metadata-rich path is a SEPARATE HTTP snapshot endpoint (Reolink Snap / Hanwha SUNAPI / Mobotix still); best->floor acquisition ladder; WSN Hanwha facts. Read before "preserving metadata over RTSP."
- `references/ecr-build-proc-acpi-failure.md` — fleet-wide ECR build regression: EVERY RUN dies at runc init (`can't mask /proc/acpi`, CVE-2025-31133). Base-image-INDEPENDENT (proven) — do NOT chase a base-image fix. Workaround = podman build + pluginctl side-load.
- `references/upload-naming-metadata-and-provenance.md` — pywaggle upload naming/metadata, timestamps, JPG/EXIF provenance, event-log linking, ns-uniqueness pitfall
- `templates/plugin-app.py` — minimal sensor plugin template
- `templates/ml-plugin-app.py` — ML vision plugin template (YOLO11-style with Camera, argparse, --image-dir, --snapshot-url with fetch_snapshot(), iter_image_dir, self-describing env.count.total with classes meta, topic name sanitization, RawDescriptionHelpFormatter epilog)
- `templates/ml-plugin-Dockerfile` — Dockerfile for ML plugins (nvcr.io/nvidia/pytorch base, model baking patterns)
- `templates/sage.yaml` — complete sage.yaml with inputs section
- `templates/job.yaml` — job YAML with science rules and success criteria reference
- `scripts/query-data.py` — standalone data query script (no sage-data-client needed)
- `references/ml-plugin-patterns.md` — production ML plugin patterns: base image selection, model baking, sidecar architecture, BioCLIP/vLLM specifics, measurement topics
- `references/runtime-packaging-patterns.md` — container runtime patterns: one-shot execution model, k3s/containerd caching, imagePullPolicy, Dockerfile layer ordering, cold-start optimization, reference plugin analysis
- `references/ecr-plugin-examples.md` — real ECR plugin examples (yolov7-fire): Dockerfile patterns, model hosting options, ECR API for inspecting existing plugins
- `references/ecr-image-generation.md` — programmatic ECR icon (512×512) and science image (1920×1080) generation with Pillow: design principles, color palettes, pipeline visualization, quality checklist
- `references/testing-patterns.md` — GPU-based testing: real model inference, pywaggle local output format, test harness utilities, `--image-dir` batch mode pitfalls, meaningful upload filenames, COCO topic name sanitization, `--add-no-detect-text` feature, integration test elimination rationale
- `references/pluginctl-camp-guide.md` — camp onboarding for pluginctl on Thor: build/run/logs workflow, sudo requirement, Dockerfile rules, vs podman/sesctl
- `references/pluginctl-sideload-and-node-build.md` — side-load vs SES, registry workarounds, podman import on node
- `references/direct-node-testing.md` — testing plugins directly on Thor/DGX nodes without Docker: rsync, shared venv, per-plugin run commands, unified memory pitfalls, Samba over Tailscale for Mac Finder access, clean.sh for pre-transfer cleanup
- `references/docker-build-deploy.md` — building Docker images for Blackwell nodes: base image selection (25.08-py3 for both DGX Spark sm_121 + Thor sm_110), pip constraints file (freeze torch+torchvision+numpy), OpenCV fix, --runtime=nvidia (not --gpus all), NVIDIA Container Toolkit setup, local testing, ECR portal submission, docker-save transfer, pluginctl deploy workflow (including --resource memory for OOMKilled prevention, k3s ctr images import)
- `references/camera-rtsp-patterns.md` — pywaggle Camera device resolution chain, RTSP URL formats by vendor (Reolink, Axis, Hikvision, Hanwha/Wisenet, ONVIF), HTTP snapshot API (Reolink CGI with low-res params), --snapshot-url flag for HTTP-only cameras, using RTSP with Sage plugins, troubleshooting
- `references/rtsp-vs-still-metadata-acquisition.md` — WHY RTSP H.264/H.265 has NO per-frame JPEG metadata; the metadata-preserving path is the vendor HTTP still (Reolink cmd=Snap / Hanwha SUNAPI stw-cgi / Mobotix current.jpg), NOT RTSP video. 3-case acquisition table + Hanwha XNV-8081Z/XNF-8010RV WSN camera notes + verify-before-build open items
- `references/hanwha-xnp6400rw-audio.md` — XNP-6400RW audio capture: no built-in mic, SPM-4210 I/O Box required, RTSP audio extraction with ffmpeg, alternative audio input paths for BirdNET
- `references/reolink-http-snapshot.md` — Reolink HTTP snapshot CGI API: URL format, low-res parameters (&width=640&height=360 for 38x bandwidth savings on LTE), --snapshot-url plugin flag, bandwidth estimation table
- `references/reolink-focus-control.md` — Reolink focus/zoom control via HTTP API: GetZoomFocus, StartZoomFocus (FocusPos/ZoomPos), SetAutoFocus (disable/enable), lock-focus workflow, curl examples
- `references/cloud-trigger-notifications.md` — Cloud trigger / external notification pattern: polling data API, Sage storage image download (curl -L, NRP propagation delay/outages, diagnostic steps), Slack text webhooks + image uploads (bot token + slack_sdk files_upload_v2), secret management, YOLO COCO class reference, multi-measurement watcher (bird+person+fork), BioCLIP species enrichment (query env.species.species when YOLO triggers, include species name in Slack alert), reference implementations (hummingbird-watcher, wildfire, weather)
- `references/audio-classification-models.md` — Wildlife audio classification models for edge: BirdNET V2.4 (primary), Google Perch 2.0 (alternative), BatDetect2, BattyBirdNET, AnuraSet, YAMNet, NatureLM-audio. Edge deployment matrix, ARM64 notes, plugin development guidance, test audio sources (Xeno-Canto v3 API key required, Wikimedia rate limits, geographic matching rule).
- **Never commit credentials to git**: Camera URLs with inline credentials (e.g. `http://user:pass@IP/...`) must NEVER appear in committed files — GitHub secret scanning flags them. Use placeholders (`CAMERA_URL_HERE`) in job YAMLs and docs. If credentials are accidentally committed, scrub all history with `pip install git-filter-repo && git filter-repo --replace-text replacements.txt --force && git push --force origin main`. Format: `old_string==>new_string` one per line. The `filter-repo` command removes the `origin` remote — re-add with `git remote add origin URL` then `git push --set-upstream origin main`.
- **Reolink FLV audio: always use sub-stream**: When pulling audio from a Reolink camera via HTTP FLV, use `channel0_sub.bcs` not `channel0_main.bcs`. ffmpeg receives the full FLV (video + audio) over the network before discarding video locally. Sub-stream is 640x360 H.264 (~500 kbps) vs main stream 3840x2160 H.265 (~8-15 Mbps) — 30-50x less bandwidth for identical audio. Native audio is AAC 16 kHz (8 kHz Nyquist); ffmpeg upsamples if `-ar 48000` is requested but no real information above 8 kHz. Set `--bandpass-fmax 8000`. See `references/reolink-audio-capture.md`.
- **Reolink silent audio gotcha**: The FLV stream contains an audio track header even when the camera mic is disabled in settings. ffmpeg completes without error, produces a valid WAV file — but it's pure silence (no background noise). BirdNET reports 0 detections, which looks like "no birds" but actually means "mic is off." Always listen to the raw capture first. Enable mic via API: `curl -s "http://IP:PORT/api.cgi?cmd=SetEnc&user=U&password=P" -d '[{"cmd":"SetEnc","action":0,"param":{"Enc":{"channel":0,"audio":1}}}]'`. See `references/reolink-audio-capture.md`.
- **Reolink API may require token auth (not just URL credentials)**: Short-session auth (`user=X&password=Y` in URL) works for some Reolink commands but some models/endpoints return `rspCode: -6` ("please login first"). Fall back to token auth: POST Login command, get token name, pass as `&token=TOKEN` on subsequent calls. Token expires after leaseTime (typically 3600s). See `references/reolink-focus-control.md`.
- **Preserve old CLI arg semantics when rewriting plugins**: When rewriting a plugin from scratch, compare old vs new CLI args explicitly. If the old code supported bounded recording cycles (`--num_rec 6 --silence_int 1`), the new code must too (`--num-recordings 6 --interval 1`). Dropping a capability (e.g. replacing finite `--num_rec` with infinite `--interval`) is a regression even if the new design seems cleaner. The user WILL notice.
- **Make job YAMLs portable — auto-detect node-specific values at runtime**: Plugins should auto-detect values that vary per node (lat/lon, camera IPs, sensor names) rather than hard-coding them in job YAMLs. Pattern: read from `/etc/waggle/node-manifest-v2.json` (mounted in k3s pods at `/etc/waggle/`). Available fields: `gps_lat`, `gps_lon`, `vsn`, `name`, `address`, `sensors` (array with `uri`, `hardware.hw_model`). Fall back gracefully when manifest is missing (local testing). This allows the same job YAML to deploy across multiple nodes without modification. Similarly, compute time-dependent values (week of year, season) at runtime rather than baking them into config.
- **Test audio committed to git (no runtime downloads)**: Audio test files MUST be committed to the repo (like vision plugin test images). No download-at-runtime scripts. Convert WAV→MP3 to keep size manageable (~16 MB for 9 files vs 54 MB WAV). MP3 compression may shift confidences slightly — always baseline from the committed MP3, never from originals. Use `generate_manifest.py` to rebuild `manifest.json` after conversion, then update test expectations in `run-tests.sh`. Check each file individually — some will be stable (e.g. single-species recordings at 99%+), others with close top-2 scores may flip. **CRITICAL**: when converting, verify top-1 species didn't change before deleting the WAV — if it did, either keep that file as WAV or update the test baseline to the new MP3 top-1.
- `references/camera-audio-capabilities.md` — Camera audio comparison for BirdNET: Mobotix M16 (built-in mic, best option), XNV-8081Z (audio input on body), AXIS Q6055-E (multicable), XNP-6400RW (no audio without I/O box). RTSP URLs per vendor, audio quality impact on BirdNET (16 KHz = 8 KHz Nyquist covers most passerines), test capture script, troubleshooting.
- `references/reolink-audio-capture.md` — Reolink audio for BirdNET: FLV stream over HTTP when RTSP port is unmapped (`/flv?port=1935&app=bcs&stream=channel0_sub.bcs`), use sub-stream to minimize bandwidth (640x360 vs 4K), native audio is AAC 16 kHz (8 kHz Nyquist), focus control API (StartZoomFocus with token auth), audio quality comparison table (USB > Reolink > M16).
- Sage infra issues report: `~/AI-projects/sage-infra-issues-2026-06-18.md` — 5 issues: NRP storage sync broken globally, ECR multi-arch QEMU failure, pybioclip 2.5 support missing, BioCLIP 2.5 OOM at 8Gi/16Gi, SSH agent key loss
- `references/bioclip-25-upgrade.md` — BioCLIP 2 → 2.5 Huge upgrade: model comparison table, text embeddings location, pybioclip patch procedure (string matching pitfalls), Dockerfile pattern, test results, upgrade checklist
