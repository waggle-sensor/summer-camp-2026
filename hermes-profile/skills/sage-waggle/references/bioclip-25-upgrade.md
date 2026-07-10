# BioCLIP 2.5 Huge Upgrade Reference

## Model Comparison

| | BioCLIP 2 | BioCLIP 2.5 Huge |
|---|---|---|
| Architecture | ViT-L/14 (~430M params) | ViT-H/14 (~1B+ params) |
| Training data | TreeOfLife-200M (200M images) | TreeOfLife-200M + 19M more (219M) |
| Model string | `hf-hub:imageomics/bioclip-2` | `hf-hub:imageomics/bioclip-2.5-vith14` |
| Weights size | ~1.7 GB safetensors | ~4-5 GB safetensors |
| Text embeddings | ~2.5 GB (.npy) | ~3.0 GB (.npy) |
| GPU memory | ~2.5 GB inference | ~5-7 GB inference |
| k8s resources | memory=8Gi,limit.memory=16Gi | memory=16Gi,limit.memory=32Gi |
| Species accuracy | 55.6% mean (10-benchmark) | 61.3% mean (+5.7%) |
| Hummingbird test | 97% confidence | 100% confidence |
| License | MIT | MIT |
| HuggingFace | imageomics/bioclip-2 | imageomics/bioclip-2.5-vith14 |

## Text Embeddings Location

Both models' text embeddings live in the `imageomics/TreeOfLife-200M` **dataset** repo
(not the model repo) under `embeddings/`:

| File | Model | Size |
|------|-------|------|
| `txt_emb_bioclip-2.5-vith14.npy` | 2.5 | 3.0 GB |
| `txt_emb_bioclip-2.5-vith14.json` | 2.5 | 80 MB |
| `txt_emb_bioclip-2.npy` | 2.0 | 2.5 GB |
| `txt_emb_bioclip-2.json` | 2.0 | 87 MB |
| `txt_emb_species.npy` | legacy (=2.0) | 2.5 GB |
| `txt_emb_species.json` | legacy (=2.0) | 87 MB |

API to list: `https://huggingface.co/api/datasets/imageomics/TreeOfLife-200M/tree/main/embeddings`

## pybioclip Patch (Required for 2.5)

pybioclip 2.1.5 doesn't support BioCLIP 2.5. Two files need patching:

### 1. `bioclip/_constants.py`
- `TOL_MODELS` dict uses variable references (NOT string literals):
  `BIOCLIP_V1_MODEL_STR: TOL10M_HF_DATAFILE_REPO, BIOCLIP_V2_MODEL_STR: TOL200M_HF_DATAFILE_REPO`
- Add: `BIOCLIP_V25_MODEL_STR = "hf-hub:imageomics/bioclip-2.5-vith14"` and entry in `TOL_MODELS`
- Add: `TOL_EMB_FILES` dict mapping model strings to `(npy_filename, json_filename)` tuples

### 2. `bioclip/predict.py`
- Import line is on a continuation line: `    HF_DATAFILE_REPO_TYPE, BIOCLIP_MODEL_STR, TOL_MODELS,`
  Add `TOL_EMB_FILES` to this line (match exact indentation)
- `get_txt_emb()` hardcodes `embeddings/txt_emb_species.npy`
  Replace with: `TOL_EMB_FILES.get(self.model_str, ("txt_emb_species.npy", ...))` lookup
- `get_txt_names()` hardcodes `embeddings/txt_emb_species.json`
  Same pattern as above

### Dockerfile Pattern

Multi-line Python in Dockerfile `RUN` breaks the parser ("unknown instruction: IMPORT").
Use a separate script file:

```dockerfile
COPY patch_pybioclip.py /tmp/patch_pybioclip.py
RUN python3 /tmp/patch_pybioclip.py && rm /tmp/patch_pybioclip.py
```

Working patch script: see `sage-bioclip` repo's `patch_pybioclip.py`.

### String Matching Pitfalls
1. `TOL_MODELS` is in `_constants.py`, NOT `predict.py`
2. `_constants.py` uses variable references (`BIOCLIP_V2_MODEL_STR`), not string literals
3. The import in `predict.py` uses relative import: `from ._constants import (`
4. Match the exact indented continuation line, not the `from` line
5. Always use `assert old in src` before replacing — fail fast on version changes

## Test Results (34 images, Species rank)

High-confidence subjects where both agree:
- Hummingbird (025/026): 97%→100%, 98%→100%
- Fox squirrel (010): 99%→100%
- Eastern newt (012): 96%→100%
- Wolf/dog (007): 36%→87%
- Elk (031-034): 76-96%→100%

Overall: v2.5 confidence higher on 32/34 images, lower on 2/34.
Live production test: *Archilochus colubris* at 99.95% on Thor H00F feeder camera.

## Upgrade Checklist

1. Tag current version: `git tag v<old>`
2. Update `app.py`: `--model` default to new model string
3. Update `app.py`: docstring (model name, params, VRAM)
4. Update/create `patch_pybioclip.py` for the new model
5. Update `Dockerfile`: comment, patch step, model-bake step
6. Update `sage.yaml`: version bump, description, model default in inputs
7. Update `ecr-meta/ecr-science-description.md`
8. Build and test on DGX Spark against 34 test images
9. Compare results with baseline (same test images, same threshold)
10. Deploy to Thor with increased memory limits if needed
11. Verify live inference via `pluginctl logs`
12. Tag new version: `git tag v<new>`
