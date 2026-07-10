# Testing Sage/Waggle ML Plugins

## Strategy: Real GPU Inference Only

All tests run real model inference on GPU — no mocked/unit tests. Each plugin has exactly one test:

- **YOLO**: `test_yolo_local.py` — runs app.py as subprocess with `--image-dir`, real YOLO inference
- **BioCLIP**: `test_bioclip_local.py` — runs app.py as subprocess with `--image-dir`, real BioCLIP inference
- **vLLM**: `test_vllm_integration.py` — launches real vLLM server subprocess, sends images for inference

**Why no unit tests?** Mocked unit tests with canned detections were removed. They tested pywaggle publish logic (topic names, meta types) without GPU, but the local tests cover the same validation AND exercise the actual model, argparse, iter_image_dir, and the full main loop. Bugs like COCO topic name sanitization and `--continuous N` batch break only surface with real inference. The local tests are the authoritative tests.

**Why no integration tests (for YOLO/BioCLIP)?** Integration tests that loaded models in-process were redundant with local tests and strictly worse: they skipped app.py entirely (no argparse, no iter_image_dir, no main loop error handling), and bugs fixed in app.py had to be separately fixed in the integration test. Exception: vLLM keeps its integration test because vLLM's server-subprocess architecture doesn't fit the local test pattern (no `--image-dir`, requires server lifecycle management).

## No Fake Visual Artifacts

Unit tests that used canned/mocked detections were removed (see above). The anti-pattern they embodied: drawing bounding boxes using fake detection results (same hardcoded boxes for every image) and uploading them — producing misleading annotated images where every photo had identical green boxes at fixed coordinates. If mock-based tests are ever reintroduced, they should validate publish logic only (topic names, value types, meta compliance) and never produce visual output.

## Meaningful Upload Filenames

When uploading images via `plugin.upload_file()`, pywaggle prepends a nanosecond timestamp: `{timestamp}-{original_filename}`. Using `tempfile.NamedTemporaryFile(suffix=".jpg")` produces unreadable names like `1781560483-tmpjoktpbnb.jpg`. Instead, derive the filename from the source image:

```python
# BAD: random temp name
tmp = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
cv2.imwrite(tmp.name, annotated)
plugin.upload_file(tmp.name, ...)  # → 1781560483-tmpjoktpbnb.jpg

# GOOD: meaningful name derived from input
stem = os.path.splitext(source_name)[0]
tmp_path = os.path.join(tempfile.gettempdir(), f"{stem}-annotated.jpg")
cv2.imwrite(tmp_path, annotated)
plugin.upload_file(tmp_path, ...)  # → 1781560483-test-image011-annotated.jpg
os.unlink(tmp_path)
```

Convention per plugin type:
- YOLO: `{stem}-annotated.jpg`
- BioCLIP: `{stem}-classified.jpg`
- vLLM: `{stem}-described.jpg`

## Core Pattern: Don't Import app.py

ML plugins import heavy deps (torch, ultralytics, open_clip, vLLM). On test machines without GPUs these either fail to import or — worse — mocking them via `sys.modules` poisons numpy:

```python
# BAD: this breaks numpy if torch is mocked
sys.modules["torch"] = MagicMock()
from plugins.yolo_counter import app  # numpy dies on reimport
```

Instead, test the publish/upload logic directly by calling pywaggle APIs with canned detection results:

```python
import os, json, tempfile
from waggle.plugin import Plugin

def test_yolo_publish():
    with tempfile.TemporaryDirectory() as outdir:
        os.environ["PYWAGGLE_LOG_DIR"] = outdir
        
        # Canned detections (what the model would return)
        detections = {"person": 2, "car": 3}
        
        with Plugin() as plugin:
            for cls_name, count in detections.items():
                plugin.publish(
                    f"env.count.{cls_name}",
                    count,
                    meta={"camera": "bottom", "model": "yolov8n"}  # all strings!
                )
        
        # Verify data.ndjson
        ndjson_path = os.path.join(outdir, "data.ndjson")
        with open(ndjson_path) as f:
            records = [json.loads(line) for line in f]
        
        assert len(records) == 2
        assert records[0]["name"] == "env.count.person"
        assert records[0]["value"] == 2
```

## PYWAGGLE_LOG_DIR Output Format

When `PYWAGGLE_LOG_DIR` is set, pywaggle captures all publish/upload calls locally:

### data.ndjson
Each line is a JSON object:
```json
{"name": "env.count.person", "value": 2, "meta": {"camera": "bottom", "model": "yolov8n"}, "timestamp": 1718000000000000000}
```

- `name`: measurement topic (string)
- `value`: int, float, or str
- `meta`: dict of string→string (MUST be all strings)
- `timestamp`: nanosecond epoch (int)

Upload events also appear as lines with `name="upload"`.

### uploads/
Files passed to `plugin.upload_file()` are copied here as `{timestamp}-{original_name}`.

## Test Harness Utilities

Shared across all plugin tests:

```python
def setup_test_output(test_name):
    """Create clean output directory, set PYWAGGLE_LOG_DIR."""
    outdir = os.path.join("tests/output", test_name)
    os.makedirs(outdir, exist_ok=True)
    os.environ["PYWAGGLE_LOG_DIR"] = outdir
    return outdir

def parse_output(outdir):
    """Parse data.ndjson into list of dicts."""
    ndjson = os.path.join(outdir, "data.ndjson")
    with open(ndjson) as f:
        return [json.loads(line) for line in f]

def get_test_images(test_dir="tests/test-images"):
    """Return sorted list of test image paths (skips dotfiles like macOS ._* resource forks)."""
    exts = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff", ".webp"}
    return sorted(
        os.path.join(test_dir, f) for f in os.listdir(test_dir)
        if os.path.splitext(f)[1].lower() in exts
        and not f.startswith(".")
    )

def print_report(test_name, records, outdir):
    """Print summary: measurement counts, upload counts, pass/fail."""
    measurements = [r for r in records if r["name"] != "upload"]
    uploads = [r for r in records if r["name"] == "upload"]
    print(f"  Measurements: {len(measurements)}")
    print(f"  Uploads: {len(uploads)}")
```

## Topic Name Sanitization (COCO Multi-Word Classes)

pywaggle topic names must match `[a-z0-9_]` joined by `.`. YOLO COCO classes include multi-word names with spaces: `dining table`, `traffic light`, `potted plant`, `hot dog`, `fire hydrant`, `stop sign`, `tennis racket`, `cell phone`, `teddy bear`. Publishing `env.count.dining table` raises `ValueError`.

**Always sanitize class names before building topic strings:**
```python
for cls_name, count in counts.items():
    safe_name = cls_name.replace(" ", "_").replace("-", "_")
    topic = f"env.count.{safe_name}"
    plugin.publish(topic, count, timestamp=ts, meta={...})
```

This bug is particularly insidious: in a loop that publishes per-class counts then a total, the classes before the offending name succeed, but the exception skips `env.count.total` and the annotated image upload. The image appears to have zero detections in test reports. Diagnosis: grep the NDJSON for images that have `env.count.<class>` records but no `env.count.total`.

## Meta Value String Compliance Check

Every test should verify meta values are strings (pywaggle crashes otherwise):

```python
for record in records:
    if "meta" in record and record["meta"]:
        for k, v in record["meta"].items():
            assert isinstance(v, str), f"Meta key '{k}' has non-string value: {v!r} ({type(v).__name__})"
```

## Testing Architecture Summary

The project uses one real-GPU test per plugin:

1. **YOLO / BioCLIP** — local tests (`test_<plugin>_local.py`): run `app.py` as a subprocess via `subprocess.run()`, parse NDJSON output, produce annotated images, JSON reports, per-image breakdowns with ASCII bar charts. CLI flags for confidence, classes, verbosity. Run by `run-tests.sh` and `run-all-tests.sh`.
2. **vLLM** — integration test (`test_vllm_integration.py`): launches vLLM server subprocess, sends images via HTTP, publishes via pywaggle. Kept because vLLM's server-subprocess architecture doesn't fit the local test pattern.

**Eliminated levels**: Unit tests (mocked models, no GPU) and redundant integration tests (in-process model loading) were removed — they duplicated coverage while missing real bugs.

### Local Standalone Test Pattern (test_<plugin>_local.py)

Standalone scripts that run a real model against real test images and report accuracy. These live alongside the automated tests but are run manually for interactive validation.

**Example (BioCLIP):** `tests/test_bioclip_local.py`
- `--rank <rank>` — test a single taxonomic rank (Kingdom, Phylum, Class, Order, Family, Genus, Species)
- `--all-ranks` — test all 7 ranks sequentially
- `--min-confidence <float>` — fail if top prediction confidence is below threshold (default: 0.50)
- `--verbose` — print full top-5 predictions per rank

**Example (YOLO):** `tests/test_yolo_local.py`
- `--classes <cls1,cls2>` — filter detections to specific YOLO classes (e.g. `--classes bird,person`)
- `--confidence <float>` — confidence threshold (default: 0.25, mapped to app.py's `--conf-thres`)
- `--iou <float>` — IoU threshold for NMS (default: 0.45, mapped to app.py's `--iou-thres`)
- `--add-no-detect-text` — (default: ON) for images with zero detections, saves a copy with green "detected no objects" text in the bottom-left corner to the uploads directory. Font scales relative to image width (~12pt at 1000px) on a dark background for readability. Ensures all test images produce output in `uploads/`. Use `--no-add-no-detect-text` to disable. This is the default because when reviewing test output, missing images are confusing — you can't tell if an image wasn't processed or simply had no COCO objects.
- Per-image reports with ASCII confidence bars

**Note on YOLO test runner flag names**: The test runner uses `--confidence` and `--iou` (shorter names), which it maps to app.py's `--conf-thres` and `--iou-thres` when constructing the subprocess command. The app.py flags are the canonical names that match Ultralytics conventions and job YAML args.

**Common features (both):**
- Outputs JSON report to `tests/output/<test_name>/report.json`
- Auto-discovers images from `tests/test-images/`
- CI-friendly exit codes (0=pass, 1=fail, 2=no images found)

**Arg naming pitfall**: Local test runners must match the exact argparse flag names used by the plugin's app.py. YOLO uses `--conf-thres`/`--iou-thres` (not `--confidence`/`--iou`). Always verify CLI flag names against app.py before writing the local test runner.

### Real Test Image Management

Canonical location: `plugins/<name>/tests/test-images/` (flat directory, committed to git). All plugins share the same set of real images — no subdirectory per plugin, no synthetic generation step. There is no `sample-images/` directory and no `generate_test_images.py` — those were removed in favor of committed real images.

Test harness utility for image discovery:

```python
TEST_IMAGES_DIR = os.path.join(os.path.dirname(__file__), "test-images")

def get_test_images():
    """Get test images, filtering out macOS ._* resource fork files."""
    if not os.path.isdir(TEST_IMAGES_DIR):
        return []
    exts = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff", ".webp"}
    return sorted(
        str(p) for p in Path(TEST_IMAGES_DIR).iterdir()
        if p.suffix.lower() in exts and p.is_file()
        and not p.name.startswith(".")
    )
```

### Testing `--image-dir` Mode

Plugins with `--image-dir` support (YOLO, BioCLIP) have a second input path that must be tested independently of `--stream`. Common pitfalls:

1. **`--continuous N` breaks batch mode** (critical, caught June 2026): The typical main-loop pattern `if args.continuous != "Y": break` fires after every image — including when using `--image-dir`. Result: only the FIRST image in the directory gets processed, then the plugin exits cleanly with valid output. This is extremely hard to spot because nothing errors — the NDJSON just has fewer records than expected. **Fix**: `if args.continuous != "Y" and not using_image_dir: break`. The directory iterator's `StopIteration` exception (caught at the top of the loop) handles batch exit.
2. **Missing `import os`**: The `--image-dir` code path uses `os.listdir()` and `os.path.join()`, but if the plugin was initially developed and tested with `--stream` only, `import os` may be missing. Always test both modes.
3. **`IMAGE_EXTENSIONS` filter**: Directory mode should filter by extension (`{".jpg", ".jpeg", ".png", ...}`) AND skip dotfiles (`not name.startswith(".")`) to exclude non-image files (README, .DS_Store, macOS `._*` resource forks).
4. **`iter_image_dir()` pattern**: Yields `(path, frame, timestamp)` tuples matching the Camera snapshot interface. This lets the main loop handle both modes with similar code.
5. **Verify batch results**: After any `--image-dir` run, always check that the NDJSON record count matches the image count. A mismatch (especially exactly 1 record) indicates the `--continuous N` bug above.

Integration tests should exercise directory mode explicitly:
```python
def test_image_dir_mode(self):
    """Run plugin with --image-dir pointing to test-images/."""
    img_dir = os.path.join(os.path.dirname(__file__), "test-images")
    result = subprocess.run(
        [sys.executable, APP_PATH, "--image-dir", img_dir, "--continuous", "N"],
        capture_output=True, text=True, timeout=120,
        env={**os.environ, "PYWAGGLE_LOG_DIR": self.outdir},
    )
    assert result.returncode == 0
```

### Accuracy Benchmarks (Real Images, DGX Spark)

BioCLIP2 on InsectCam01 hummingbird (3840x2160):
| Rank | Top Prediction | Confidence | Time |
|------|---------------|------------|------|
| Kingdom | Animalia | 99.95% | 7.02s |
| Phylum | Chordata | 99.88% | 6.90s |
| Class | Aves | 99.87% | 6.89s |
| Order | Apodiformes | 97.14% | 8.15s |
| Family | Trochilidae | 97.26% | 8.23s |
| Genus | Archilochus | 97.97% | 8.28s |
| Species | *Archilochus colubris* | 97.97% | 6.99s |

Higher taxonomic ranks aggregate species-level probabilities, so higher ranks ≥ species confidence. Per-rank inference is ~7-8s (includes both image encoding + text similarity search over the full taxonomy).

YOLO11x on InsectCam01 hummingbird (3840x2160, DGX Spark):
- Detection: 1 bird detected, ~33.7ms inference
- Tested via: unit test (mocked), integration test (real model), local standalone runner
- Both `--stream` (single image) and `--image-dir` (directory scan) modes verified

## Self-Contained Plugin Test Structure

Each plugin carries its own complete test suite as a subdirectory. No cross-plugin dependencies — a plugin can be extracted from the monorepo and still have working tests.

### Directory layout (per plugin)
```
plugins/<plugin-name>/
├── app.py
├── Dockerfile
├── sage.yaml
├── overview.md
├── ecr-meta/
├── jobs/
│   └── <plugin-name>-job.yaml   # Per-plugin job YAML for edge scheduler
└── tests/
    ├── run-tests.sh           # Self-contained runner (activates venv, runs test)
    ├── test_<plugin>_local.py # Local test (real GPU, runs app.py as subprocess, full reporting)
    ├── test_harness.py        # Copy of shared harness (self-contained, not imported cross-plugin)
    └── test-images/           # Test images (committed to git, flat directory, no subdirs)
```

### Shared infrastructure (top-level `tests/`)
```
tests/
├── .venv/                     # Shared venv (too large to duplicate per plugin)
└── run-all-tests.sh           # Discovers plugins, runs each plugin's test (GPU required)
```
### Key design decisions
- **test_harness.py is COPIED into each plugin**, not shared via import. Self-contained means zero cross-deps. If the harness changes, update all copies.
- **Shared venv** stays at top-level `tests/.venv` — duplicating a multi-GB venv per plugin is wasteful. Per-plugin `run-tests.sh` activates `../../tests/.venv`.
- **run-all-tests.sh** auto-discovers plugins by scanning `plugins/*/tests/test_*.py` (skips `test_harness.py`). All tests require GPU. Reports per-plugin pass/fail summary.
- **Test paths are relative to TESTS_DIR**: all test files use `TESTS_DIR = Path(__file__).parent` and resolve images as `TESTS_DIR / "test-images"`. No plugin-name subdirectory — images are directly in `test-images/`.

### Migration pitfall
When moving tests from a shared `tests/` directory into per-plugin `tests/` subdirectories, grep ALL files for old path patterns (`PROJECT_DIR`, `../../tests/test-images`, `cd Sage-agents && ...`) and rewrite to plugin-relative paths. Check both Python files AND markdown docs (overview.md frequently hardcodes test paths in example commands).

### pytest namespace collision (pyproject.toml required)

When running `pytest` from the repo root to collect tests across all plugins, pytest's default import mode (`prepend`) treats identically-named files (e.g. `test_harness.py` in each plugin's `tests/`) as the same module. The second plugin's `test_harness` silently resolves to the first plugin's cached module — tests pass or fail for the wrong reasons.

**Fix**: add `pyproject.toml` at repo root:
```toml
[tool.pytest.ini_options]
import_mode = "importlib"
```

This makes pytest treat each file as its own namespace — no module name collisions.

**Anti-pattern — do NOT add `__init__.py` to test dirs**:
Adding `__init__.py` to `plugins/<name>/tests/` turns the directory into a Python package. Since test files use relative imports like `from test_harness import ...`, this breaks with `ModuleNotFoundError` because Python now expects package-qualified imports. The `importlib` mode is the correct fix — it works without `__init__.py` and doesn't change the import semantics of the test files themselves.

## Required Test Venv Packages

```
pywaggle[all]>=0.56.0
numpy
opencv-python-headless
Pillow
ffmpeg-python   # required by waggle.data.vision Camera import
```

Note: `ffmpeg-python` is needed even if you don't use video — the `Camera` class imports it unconditionally.

## Integration Testing: vLLM Sidecar Pattern

Integration tests for the vLLM plugin launch a real server subprocess, wait for model load, then issue inference requests. Key patterns:

### Server Launch — Log to File, Not PIPE
```python
log_path = os.path.join(output_dir, "server.log")
server_log = open(log_path, "w")
proc = subprocess.Popen(
    [sys.executable, "-m", "vllm.entrypoints.openai.api_server",
     "--model", MODEL, "--port", str(PORT),
     "--gpu-memory-utilization", "0.58",  # unified memory: only ~60% usable (OS shares pool)
     "--max-model-len", "4096",
     "--dtype", "bfloat16",
     "--trust-remote-code",
     "--enforce-eager",                   # required: CUDA graph capture OOMs on 32B+ models
     "--no-enable-log-requests"],          # NOT --disable-log-requests (removed in 0.23.0)
    stdout=server_log,
    stderr=subprocess.STDOUT,
)
```

**Why file, not PIPE**: PIPE can deadlock on large vLLM startup output. A file also provides post-mortem debugging when the server fails silently.

### Verify Server Actually Started
After Popen, always check the child didn't immediately exit:
```python
time.sleep(2)
if proc.poll() is not None:
    # Server already exited — read log for error
    with open(log_path) as f:
        print(f.read())
    raise RuntimeError(f"vLLM server exited with code {proc.returncode}")
```

A common silent failure: unrecognized CLI flag causes argparse to exit(2), but the parent sees no error because stderr went to PIPE. The child shows as `<defunct>` in `ps`.

### Health Check Polling
```python
def wait_for_ready(base_url, max_wait=900, poll=15):
    start = time.time()
    while time.time() - start < max_wait:
        try:
            r = requests.get(f"{base_url}/health", timeout=5)
            if r.status_code == 200:
                return True
        except requests.ConnectionError:
            pass
        time.sleep(poll)
    return False
```

Budget 10-15 min for first run (model download). Subsequent runs with cached weights: ~7 min total (405s model load + 113s Triton JIT warmup on first inference). Set test timeout to at least 2400s (40 min) to cover download + load + warmup + actual tests.

### Cleanup
Always terminate the server after tests, even on failure:
```python
try:
    # ... run tests ...
finally:
    proc.terminate()
    proc.wait(timeout=30)
```
