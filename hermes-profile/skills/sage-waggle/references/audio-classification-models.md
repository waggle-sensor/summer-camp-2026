# Wildlife Audio Classification Models for Sage Edge Nodes

Summary of models evaluated in June 2026 for the bird-diversity plugin.
Full analysis committed to https://github.com/flint-pete/birdnet/blob/main/RESEARCH.md

## Primary: BirdNET V2.4

- `pip install birdnet` (v0.2.16) — lightweight inference library
- 6,522 classes: ~6,000 birds + ~100 non-avian (frogs, crickets, katydids, toads)
- EfficientNetB0-like, 50.5 MB (FP32), 0.826 GFLOPs
- TFLite (CPU) + ProtoBuf (GPU, x86_64 only)
- 3-second chunks at 48 kHz, dual mel-spectrograms
- eBird geo-filtering by lat/lon/week
- MIT code, CC BY-NC-SA 4.0 models (research/education = free)
- Runs real-time on Raspberry Pi 4 (ARM64, CPU-only)
- **ARM64 GPU not supported** in standard package — TFLite CPU is the path for Thor
- GitHub: https://github.com/birdnet-team/BirdNET-Analyzer

## Alternative: Google Perch 2.0

- ~15,000 species (birds, frogs, insects, mammals)
- EfficientNet-B3, 12M params (embeddings) + 91M (classifier)
- **Apache 2.0** license (fully permissive, better than BirdNET's CC-NC)
- TFLite/ONNX exports, runs in BirdNET-Go on ARM64
- "Agile modeling" — few-shot classifiers on top of embeddings
- GitHub: https://github.com/google-research/perch

## Complementary Models

| Model | What | Size | License | Edge-ready |
|-------|------|------|---------|------------|
| BatDetect2 | Bat echolocation | few MB | CC-BY-NC-4.0 | Yes (RPi, Jetson) |
| BattyBirdNET | Bats (11 regions) | TFLite | CC-BY-NC-SA | Yes (RPi) |
| AnuraSet | 42 frog species | PyTorch CNN | MIT/CC-BY 4.0 | Needs ONNX conversion |
| YAMNet | 521 audio events | 3.7 MB | Apache 2.0 | Yes (anything) |
| NatureLM-audio | Zero-shot bioacoustics | 0.7B params | CC-BY-NC-SA | Thor only |

## BirdNET-Go (Multi-Model Platform)

Go application running BirdNET + Perch + BattyBirdNET in parallel.
Pre-built Docker images for linux/arm64. Real-time with web dashboard.
GitHub: https://github.com/tphakala/birdnet-go

## BirdNET Python API Reference (tested June 2026)

Three pip packages exist — use the right one:
| Package | Install | Use case |
|---------|---------|----------|
| `birdnet` | `pip install birdnet` (v0.2.16) | Core inference. **Use this for edge plugins.** |
| `birdnet-analyzer` | `pip install birdnet-analyzer` (v2.4.0) | Full suite (GUI, training, eval). Not for edge. |
| `birdnetlib` | `pip install birdnetlib` | Third-party wrapper by Joe Weiss. |

### Model loading
```python
import birdnet
acoustic = birdnet.load("acoustic", "2.4", "tf")  # ~77 MB download
geo = birdnet.load("geo", "2.4", "tf")            # ~46 MB download
# Models cached at ~/.local/share/birdnet/
# Override: export BIRDNET_APP_DATA=/path/to/models
```

### Prediction API (key parameter names)
```python
predictions = acoustic.predict(
    "recording.wav",               # Path or Iterable[Path]
    top_k=5,                       # Max predictions per 3s chunk
    default_confidence_threshold=0.25,  # NOT min_confidence
    sigmoid_sensitivity=1.0,       # NOT sensitivity
    overlap_duration_s=0.0,        # NOT overlap
    custom_species_list=species_set,  # Set[str] from geo model
    apply_sigmoid=True,
    half_precision=False,
    device="CPU",                  # "CPU" only on ARM64
    show_stats=None,               # "minimal", "progress", "benchmark"
)
df = predictions.to_dataframe()
# Columns: input, start_time, end_time, species_name, confidence
# species_name format: "Genus species_Common Name" (split on first "_")
```

### Geo model API
```python
geo = birdnet.load("geo", "2.4", "tf")
result = geo.predict(41.88, -87.62, week=22, min_confidence=0.03)
# Result methods: .to_set(), .to_dataframe(), .to_csv(), .to_txt()
# NOT .to_list() — that doesn't exist
species_set = result.to_set()  # Set of "Scientific_Common" strings
# Pass to acoustic model via custom_species_list=species_set
```

### API gotchas (all discovered through testing)
- No `birdnet.__version__` attribute
- `predict()` param is `default_confidence_threshold`, NOT `min_confidence`
- `predict()` param is `sigmoid_sensitivity`, NOT `sensitivity`
- `predict()` param is `overlap_duration_s`, NOT `overlap`
- `GeoPredictionResult` has `.to_set()` and `.to_dataframe()`, NOT `.to_list()`
- GPU not supported on ARM64 — `device="CPU"` is the only option for Thor/DGX Spark
- `predict()` accepts single path or Iterable of paths
- Auto-downloads models on first call (blocks until complete)
- Audio is auto-resampled to 48 kHz internally

### Model formats available (from Zenodo)
| Format | Size | Use case |
|--------|------|----------|
| ProtoBuf (SavedModel) | 124.5 MB | CPU + GPU (FP32) |
| TFLite FP32 | 76.8 MB | CPU only |
| TFLite FP16 | 53.0 MB | CPU only |
| TFLite INT8 | 45.9 MB | CPU only, fastest on edge |

## Plugin Development Notes

- Use `birdnet` package (not `birdnet-analyzer`) for edge plugins
- Model auto-downloads on first use to `~/.local/share/birdnet/`
- Bake model into Docker image at build time (no runtime download):
  ```dockerfile
  RUN python3 -c "import birdnet; birdnet.load('acoustic','2.4','tf'); birdnet.load('geo','2.4','tf')"
  ```
- **Dockerfile base**: Use `python:3.12-slim` (not NVIDIA base) since BirdNET is CPU-only on ARM64. System deps: `ffmpeg libsndfile1 libasound2-dev`
- Audio input: pywaggle `Microphone` API or `--input <file>` for testing
- Support `--dry-run` flag for testing without pywaggle (import Plugin only when needed)
- Publish per-species: `env.detection.audio.<scientific_name>` with meta for common_name
- Publish summary: `env.detection.audio.summary` as JSON with unique species + counts
- Dependencies: `birdnet>=0.2.16`, `librosa>=0.11`, `numpy`, `soundfile`, `pywaggle[audio]`
- The birdnet library pulls in tensorflow (~500 MB) as a dependency — budget Docker image size accordingly
- Plugin repo: https://github.com/flint-pete/birdnet (forked from dariodematties/BirdNET_Lite_Plugin)
- Full research survey committed to repo: RESEARCH.md
- Repo renamed from `bird-diversity` to `birdnet` (one plugin per model family)

## Test Audio Sources

**BirdNET official test data** (GitHub):
```bash
# Clone: https://github.com/birdnet-team/birdnet-test-data
# Key files:
#   soundscape/soundscape.wav — multi-species (Chickadee, Junco, House Finch, Goldfinch)
#   embeddings/embeddings-dataset/s1/file01-12.wav — Red-backed Shrike (99%+)
#   embeddings/embeddings-dataset/s2/file01-12.wav — Eurasian Wryneck (99%+)
#   embeddings/search_sample.mp3 — Blue Jay (99.7%)
# WARNING: training/ directory files are DUMMY DATA (identical SHA hashes)
```

**IMPORTANT: test audio must match deployment geography.** Use North
American species for NA-targeted plugins — European species (Red-backed
Shrike, Eurasian Wryneck from the BirdNET test data s1/s2 files) should
be excluded from NA test suites even though BirdNET's model is global.

**Xeno-Canto API**: v2 retired (404), v3 requires API key (free account at xeno-canto.org).
```
GET https://xeno-canto.org/api/3/recordings?query=Turdus+migratorius&key=YOUR_KEY
# Returns JSON with direct MP3 download URLs
# v2 endpoint returns: {"error":"server_error","message":"Xeno-canto API v2 is no longer available..."}
```

**Wikimedia Commons**: CC-licensed bird audio available via API.
Rate-limited aggressively (429 after ~10 requests). Use 2s delays.
Search: `action=query&list=search&srsearch=<species>+bird+call&srnamespace=6`
Get URL: `action=query&titles=<File:name>&prop=imageinfo&iiprop=url`

**Zenodo labeled dataset**: https://zenodo.org/records/7828148
- 22 species, 967 recordings, 6,537 annotations, WAV format
