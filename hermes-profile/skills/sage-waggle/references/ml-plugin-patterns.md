# Production ML Plugin Patterns for Sage

Distilled from PTZ_APP (github.com/plebbyd/PTZ_APP) reference implementation and three working plugins built in June 2025. Updated with integration test benchmarks on DGX Spark (GB10 Blackwell, 128GB unified, CUDA 13.0).

## Base Image Selection

For GPU-accelerated ML plugins, use `nvcr.io/nvidia/pytorch:24.06-py3` instead of `waggle/plugin-base:1.1.1-ml`. The NVIDIA image has:
- PyTorch 2.x with current CUDA
- Full CUDA runtime + cuDNN
- Better compatibility with Ultralytics, open_clip, vLLM, transformers

The waggle/plugin-base images are fine for non-ML or lightweight inference.

## Model Weight Baking

Edge nodes may not have internet access. Always pre-download model weights into the Docker image at build time. Models must be baked at a **known, explicit path** — never rely on library auto-download cache directories that can change between versions.

### Principle: Explicit paths, not cache-dependent

The plugin must be fully self-contained. A Kubernetes pod starts the container and runs inference — there's no network fetch, no first-run download. The model weights are a fixed layer in the Docker image.

### Pattern A: Direct download to explicit path (preferred for YOLO, small models)

Learned from production ECR plugins (e.g. `giorgio808/yolov7-fire`). Download the `.pt` file to a known path using `curl` or `ADD` at build time:

```dockerfile
# Option 1: curl from a release/hosting URL (most robust)
RUN curl -L -o /app/models/yolo11x.pt \
    "https://github.com/ultralytics/assets/releases/download/v8.3.0/yolo11x.pt"

# Option 2: Docker ADD from URL (simpler but less error handling)
ADD https://github.com/ultralytics/assets/releases/download/v8.3.0/yolo11x.pt /app/models/yolo11x.pt

# Option 3: ultralytics auto-download (fragile — cache path can change between versions)
# NOT recommended for production ECR plugins
# RUN python -c "from ultralytics import YOLO; YOLO('yolo11x.pt')"
```

Then in app.py, load from the explicit path:
```python
# Default model path points to baked-in weights
parser.add_argument("--model", default="/app/models/yolo11x.pt")
# ...
model = YOLO(args.model)  # loads from explicit path, no network fetch
```

**Why not auto-download?** The `ultralytics` auto-download stores weights in `~/.config/Ultralytics/` — an implementation detail that can change. The `curl` approach stores at a known path (`/app/models/`) and works even if the ultralytics version changes. It also makes the Dockerfile self-documenting about exactly which model file is baked in.

**For very large models (>500MB):** The yolov7-fire plugin demonstrated a split-file pattern — download model parts separately then `cat` them together — for reliability over constrained network connections. Not needed for YOLO11x (~110MB) but useful for BioCLIP2 or vLLM models if hosting as direct downloads.

### Pattern B: HuggingFace models to explicit cache directory

For HF-hosted models (BioCLIP, vLLM/Qwen), use `huggingface-cli` to a fixed cache path:

```dockerfile
RUN mkdir -p /hf_cache
RUN HF_HOME=/hf_cache huggingface-cli download <org>/<model> --cache-dir /hf_cache --resume

# For HF Spaces (e.g. BioCLIP demo embeddings):
# RUN HF_HOME=/hf_cache huggingface-cli download <org>/<space> --repo-type space --cache-dir /hf_cache

# Lock to offline mode at runtime — prevents accidental network fetches
ENV HF_HOME=/hf_cache
ENV TRANSFORMERS_OFFLINE=1
ENV HF_DATASETS_OFFLINE=1
```

### .gitignore

Model weight files must never be committed to git:

```gitignore
*.pt
*.pth
*.bin
*.safetensors
```

## Plugin Architecture Patterns

### Pattern 1: Direct Inference (YOLO, BioCLIP)
Model loaded in-process, inference called each cycle. Simple and reliable.

```
Camera.snapshot() → detector.detect(frame) → plugin.publish() + plugin.upload_file()
```

Key requirements.txt packages:
- `pywaggle[all]>=0.56.0` — always include
- `ultralytics>=8.3.70` — for YOLO (8.4.66+ tested)
- `pybioclip>=2.1.5` — for BioCLIP2 (recommended over raw open_clip)
- `open_clip_torch>=2.20.0` + `timm==1.0.15` — for BioCLIP (legacy, use pybioclip instead)
- `torch>=2.0.0` — shared dependency

### Pattern 2: Sidecar Server (vLLM)
Model served by a background process, plugin communicates via HTTP API on localhost.

```
app.py launches vLLM subprocess → waits for /health → sends base64 images via OpenAI-compatible API
```

Benefits: model stays loaded between cycles, can serve multiple plugins, vLLM's PagedAttention manages GPU memory efficiently.

Health check pattern:
```python
def wait_for_ready(self, max_wait=600, poll_interval=10):
    elapsed = 0
    while elapsed < max_wait:
        try:
            r = requests.get(f"{self.base_url}/health", timeout=5)
            if r.status_code == 200:
                return True
        except Exception:
            pass
        time.sleep(poll_interval)
        elapsed += poll_interval
    raise TimeoutError(...)
```

### Pattern 3: Detector Factory (PTZ_APP)
ABC-based detector hierarchy with factory pattern for multi-model support. Overkill for single-model plugins, but good pattern for combinatorial plugins:

```python
class ObjectDetector(ABC):
    @abstractmethod
    def detect(self, frame): ...

class YOLODetector(ObjectDetector): ...
class FlorenceDetector(ObjectDetector): ...
class BioCLIPDetector(ObjectDetector): ...

class DetectorFactory:
    @staticmethod
    def create(model_name, **kwargs) -> ObjectDetector: ...
```

## BioCLIP-Specific Notes

Two approaches — **pybioclip** (recommended) or raw open_clip:

### pybioclip (recommended)
- Package: `pybioclip>=2.1.5` — wraps BioCLIP2 (SigLIP2-based, ~430M params) cleanly
- Model: `hf-hub:imageomics/bioclip-2` (latest gen, better than original BioCLIP)
- API: `TreeOfLifeClassifier` for taxonomy, `CustomLabelsClassifier` for custom labels
- `predict()` returns list of dicts with rank keys (`kingdom`, `phylum`, `class`, `order`, `family`, `genus`, `species`) + `score` + `file_name`
- No manual text embedding download needed — pybioclip handles it
- Performance (DGX Spark, BioCLIP2): load 3.1s cached, warmup 3.7s, inference ~480-500ms/image
- BioCLIP 2.5 Huge (`hf-hub:imageomics/bioclip-2.5-vith14`): ViT-H/14 (~1B+ params), 61.3% mean zero-shot species accuracy (+5.7% over BioCLIP 2). Requires pybioclip patch (see below). ~5-7 GB GPU memory. On 34-image test suite: confidence higher on 32/34 images, hummingbird 97%→100%, elk 88%→100%, wolf 36%→87%. Text embeddings are ~3 GB (vs ~2.5 GB for BioCLIP 2). Docker image ~30+ GB.

### Upgrading pybioclip to support newer BioCLIP models

pybioclip 2.1.5 hardcodes a `TOL_MODELS` dict that only knows about `bioclip` and `bioclip-2`. Newer models (e.g. `bioclip-2.5-vith14`) fail with `ValueError: TreeOfLife predictions are only supported for...`. The text embeddings exist in the `imageomics/TreeOfLife-200M` dataset repo under `embeddings/` with model-specific filenames (e.g. `txt_emb_bioclip-2.5-vith14.{npy,json}`), but pybioclip's `get_txt_emb()` and `get_txt_names()` hardcode `txt_emb_species.{npy,json}`.

**Fix: monkey-patch predict.py in Dockerfile** (before the model-bake step):
1. Add the new model to `TOL_MODELS` dict pointing to `imageomics/TreeOfLife-200M`
2. Add a `TOL_EMB_FILES` dict mapping model strings to `(npy_filename, json_filename)` tuples
3. Override `get_txt_emb()` to look up the npy filename from `TOL_EMB_FILES` (fallback: `txt_emb_species.npy`)
4. Override `get_txt_names()` similarly for the json filename

See the `sage-bioclip` repo Dockerfile for the complete patch. Remove the patch when pybioclip upstream adds native support.

**Known embedding files** (in `imageomics/TreeOfLife-200M/embeddings/`):
- `txt_emb_species.{npy,json}` — BioCLIP 2 (duplicates of bioclip-2 files, for backwards compat)
- `txt_emb_bioclip-2.{npy,json}` — BioCLIP 2 (canonical)
- `txt_emb_bioclip-2.5-vith14.{npy,json}` — BioCLIP 2.5 Huge (3.0 GB npy, 80 MB json)

### Raw open_clip (legacy)
- Model: `imageomics/bioclip` (original ViT-B/16 fine-tuned on TreeOfLife-10M, 454K+ species)
- Pre-computed text embeddings: `imageomics/bioclip-demo` space → `txt_emb_species.npy` + `txt_emb_species.json`
- Download embeddings as `--repo-type space` (it's a HF Space, not a model repo)
- Load model via `open_clip.create_model_and_transforms("hf-hub:imageomics/bioclip")`
- For higher taxonomic ranks (Class, Order), aggregate species-level probabilities
- Preprocessing: Resize to 224×224, normalize with CLIP means/stds

## VLM/vLLM Edge Notes

### Model Selection by Memory Budget

| Memory | Model | Params | Size | Notes |
|--------|-------|--------|------|-------|
| 16GB (Xavier NX) | Phi-3.5-vision-instruct | 7.6B | ~15GB FP16 | Fits tight, `--gpu-memory-utilization 0.85` |
| 32-48GB | Qwen3-VL-8B-Instruct | 8B | ~16GB BF16 | Good balance for mid-range |
| 128GB (Thor/DGX Spark) | Qwen3-VL-32B-Instruct | 32B | ~67GB BF16 | Best quality that fits; latest gen. **Requires `--enforce-eager` + `--gpu-memory-utilization 0.58`** |
| 128GB (quantized) | Qwen2.5-VL-72B-AWQ | 72B | ~43GB 4-bit | More params but older gen, quantized — 32B BF16 generally better |

### Qwen3-VL-32B Configuration (128GB unified memory nodes)
```bash
python -m vllm.entrypoints.openai.api_server \
  --model Qwen/Qwen3-VL-32B-Instruct \
  --port 8199 \
  --gpu-memory-utilization 0.58 \
  --max-model-len 4096 \
  --dtype bfloat16 \
  --trust-remote-code \
  --enforce-eager \
  --no-enable-log-requests
```

- Port 8199 (non-default to avoid conflicts with other services)
- `--gpu-memory-utilization 0.58` — on 128GB unified memory (DGX Spark / Thor), vLLM reports ~121.69 GiB total but only ~70-74 GiB is actually free (OS shares the unified pool). 0.80 and 0.85 both OOM. 0.58 works reliably.
- `--enforce-eager` — **required** for 32B models on unified memory. Without it, vLLM attempts CUDA graph capture which consumes ~5GB extra memory on top of the model, causing OOM even at 0.58. Eager mode skips graph capture at the cost of ~10-15% throughput — acceptable tradeoff to avoid OOM.
- `--dtype bfloat16` — full precision, no quantization needed at 128GB
- `--trust-remote-code` required for Qwen3-VL
- Download is ~67GB — budget 10-15 min on fast connections
- vLLM 0.23.0+ has native `qwen3_vl.py` model support

**Unified memory gotcha**: Unlike discrete GPU cards where VRAM is dedicated, unified memory (GB10, Grace Hopper, Apple Silicon) shares the pool with the OS and other processes. Always check actual free memory at runtime, not total reported. The effective usable fraction is typically 55-65% of reported total, not 80-90% as with discrete GPUs.

### General vLLM Notes
- vLLM serves OpenAI-compatible API — send images as base64 data URLs in chat completions
- Two-pass prompting: detailed description + one-line summary per frame
- Use non-default port to avoid conflicts when running alongside other services
- **vLLM 0.23.0 CLI flag change**: `--disable-log-requests` was removed. Use `--no-enable-log-requests` instead. The old flag causes a silent crash (unrecognized argument → Popen child exits immediately as `<defunct>` zombie). Always check `--help` output when vLLM version changes.

### YOLO Model Scaling

| Memory | Model | Params | mAP | Inference | Notes |
|--------|-------|--------|-----|-----------|-------|
| 16GB | yolo11n.pt | 2.6M | 39.5% | ~5ms | Nano — fast but lower accuracy |
| 32GB+ | yolo11x.pt | 56.9M | 54.7% | ~20ms | Extra-large — best accuracy |

Performance (DGX Spark, yolo11x.pt): load 2.71s, warmup 0.74s, avg inference 20.6ms, robust detection

## Measurement Topic Conventions

```
env.count.<class>           — integer count per YOLO class (person, car, bird)
env.count.total             — total detections across all classes
env.species.<rank>          — top taxon name at rank (e.g. "Aves")
env.species.<rank>.confidence — confidence score
env.species.top5            — JSON array of top-5 predictions
env.scene.description       — multi-sentence scene description from VLM
env.scene.summary           — one-line scene summary from VLM
```

## Publishing pitfalls (pywaggle `plugin.publish`)

### `meta` MUST be a dict of strings → strings (silent pipeline killer)
pywaggle's `plugin.publish(name, value, timestamp=..., meta={...})` validates
that EVERY meta value is a string. A non-string (float/int/numpy) raises:
```
TypeError: Meta must be a dictionary of strings to strings.
```
This bit birdnet hard: `meta={"start_time_s": det["start_time"], ...}` passed
FLOATS, so every time a bird was actually detected the per-detection publish
crashed — yet the SUMMARY publish (which had `meta={}` / no meta) succeeded, so
the per-cycle heartbeat looked healthy while NOT A SINGLE real detection ever
reached the data API. The bug had been latent since the plugin was written;
lowering the detection threshold just made it crash MORE often (more detections
= more crashes). The symptom is "data API shows summary/heartbeat records but
zero of the per-class/per-species records the code clearly publishes."

**Rule:** stringify every meta value at the publish call:
```python
meta={"common_name": str(det["common_name"]),
      "start_time_s": str(det["start_time"]),
      "end_time_s": str(det["end_time"])}
```
The `value` (positional 2nd arg) CAN be a number — only `meta` values must be
strings. yolo and bioclip already do this (`"num_classes": str(len(counts))`,
`"confidence": str(top["confidence"])`); audit any new plugin's meta before ship.

**Reproduce a publish crash WITHOUT a broker** (catches this in local testing):
run the plugin with `PYWAGGLE_LOG_DIR=/tmp/wlog` set — pywaggle then exercises
the full publish path (incl. meta validation) and writes records to
`/tmp/wlog/data.ndjson` instead of a broker. A clean run = correct meta; a
`TypeError` = bad meta. This is the fastest way to verify publish before
building/sideloading/deploying.

### `timestamp` must be int nanoseconds
Use `timestamp=int(time.time_ns())`. A float (`time.time()`) is rejected.

## Reference Implementations

Three complete plugins at `~/AI-projects/Sage-agents/plugins/`:

1. **yolo-object-counter/** — YOLO11x detection, per-class counts, annotated image upload
2. **bioclip-species-classifier/** — BioCLIP2 via pybioclip TreeOfLifeClassifier, probability aggregation
3. **vllm-edge-inference/** — vLLM sidecar, Qwen3-VL-32B-Instruct (BF16), scene description pipeline

Each has: app.py, Dockerfile, requirements.txt, sage.yaml, ecr-meta/, jobs/, tests/, overview.md

Per-plugin job YAMLs live in each plugin's `jobs/` directory. Combined pipeline job at top-level `jobs/combined-ml-pipeline-job.yaml`.

## Integration Test Benchmarks (DGX Spark, GB10 Blackwell, 128GB unified, CUDA 13.0)

All benchmarks from passing integration tests with real models on real hardware.

| Plugin | Model | Load Time | Warmup | Avg Inference | Notes |
|--------|-------|-----------|--------|---------------|-------|
| YOLO | yolo11x.pt (56.9M params) | 2.71s (cached) | 0.74s | 20-33ms/image (resolution-dependent; ~20ms 640px, ~32ms 4K) | Robust multi-class detection |
| BioCLIP | BioCLIP2 via pybioclip (430M) | 3.1-3.2s (cached) | 3.7s | ~480-500ms/image (species), ~730ms-3.4s (class, varies with taxonomy size) | Class-level aggregates all species probs |
| vLLM | Qwen3-VL-32B-Instruct BF16 (62.49 GiB) | ~380-405s (cached) | 112.9s (Triton JIT) | 22-26s/image (description, ~85-97 tok), 5.4-5.5s (summary, ~19 tok) | Two-pass: detailed description + one-line summary, ~3.8 tok/s generation |

**vLLM warmup**: First inference after server start takes ~113s due to Triton kernel JIT compilation. Subsequent inferences are 5-10x faster. Budget total server-ready-to-first-useful-output at ~520s (load + warmup).

**vLLM server startup timeout**: Budget 2400s (40 min) for integration tests to account for model download + load + warmup. Cached weights: ~7 min (load 405s + warmup 113s).
