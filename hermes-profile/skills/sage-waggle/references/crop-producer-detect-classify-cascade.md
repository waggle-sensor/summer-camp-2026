# Crop-producer: detect→classify cascade via the shared cache

A YOLO/detector plugin can become a **producer** so a downstream classifier
(e.g. BioCLIP) consumes each detected object — with **no cross-plugin triggering
code**. The handoff is file-mediated through the shared `/local-cache`: the
detector crops each matching bbox and writes it as a v2 frame into a new crop
stream; the classifier reads crops on its own schedule. Proven on sage-yolo2
v2.1.0 (repo flint-pete/sage-yolo2, additive/off-by-default extension to the
v2.0.0 count-consumer).

## The pattern

```
image-sampler2        yolo2 (count + CROP-PRODUCE)          bioclip (classify)
 camera → cache   →   detect, count/publish              →  read each crop, classify
 <cam> stream         for each --crop-match detection:        + species record
                        crop bbox → write v2 frame
                        into <cam>-crop-<idx> stream  ─────────→
```

Key properties that make it clean:
- **Frame-anchored all the way down.** The crop INHERITS the parent frame's
  `capture_ts_ns`, so a species result traces to when the photo was taken.
- **Per-detection streams.** N objects in one frame → N crops under distinct
  `<camera>-crop-<idx>/` streams (they share capture_ts, differ by index).
- **Provenance blob.** Each crop's UserComment JSON gets a nested `source` object:
  `source_class, source_confidence, source_bbox, source_unique_id,
  detection_index` — YOLO context + full traceability for the classifier.
- **Own bounded ring.** `--crop-max-count`/`--crop-max-mb` (evict-on-either).
  RATE RULE: the classifier must drain faster than the detector fills, else crops
  evict before classification (same producer/consumer rule as the raw cache).
- **Off by default.** Empty `--crop-match` = immediate no-op; the validated
  count/upload path is untouched. Gate every new capability behind a default-off
  flag so you never disturb a verified path.

## Vendoring the v2 WRITE side (the reusable mechanics)

The v2 cache-writer lives in image-sampler2 (`metadata.py` EXIF/UserComment embed
+ `cache.py` ring/eviction). To let another plugin PRODUCE v2 frames, vendor a
curated merge (decision (B), matching the `save_match.py`/`node_info.py`
precedent — a single-repo change, no cross-repo edit):

- Merge only the WRITE pieces into one module (e.g. `crop_writer.py`):
  `build_v2_name`, `embed_all`/`build_exif_bytes`/`inject_exif` (piexif),
  `scan_ring`/`plan_evictions`/`commit_capture`, plus a `write_frame()`
  one-call helper (scan→plan→atomic tmp→fsync→os.replace).
- DROP the read-side + config-probe helpers — the consuming plugin already has
  its own reader (`consumer.py` with `parse_v2_name`/`read_frame_metadata`).
- `unique_id` = SHA256 of the crop JPEG bytes BEFORE EXIF injection (stable,
  recomputable, no self-reference paradox; it's also the classifier's dedup key).
- v2 filename: `<capture_ts_ns>-v2-<vsn>-<camera>.jpg`; MB is DECIMAL (10^6).

### The contract test that matters most
Write a test that produces a crop with the vendored writer and reads it back with
the SAME `consumer.read_frame_metadata` the classifier uses — proves
byte-compatibility. There is no automated diff (a merge, not a mirror), so THE
TESTS ARE THE SYNC CONTRACT. Register the vendored module in `VENDORED.md` with
its divergence list + this obligation.

## Offline e2e without a GPU (Stage-4 style)

Prove the whole cascade offline: build a synthetic multi-object frame with
distinctly-colored regions, run the real crop path with a FAKE detector returning
known bboxes, then have the test act as the DOWNSTREAM CONSUMER — scan each crop
stream, read metadata back, and assert crop PIXELS match the source region
(dominant-color check) + provenance intact + capture_ts inherited. No node, no
YOLO, no camera.

## Ship checklist (Stage-6)
VERSION + sage.yaml version bump (minor for additive); surface every new flag in
sage.yaml `inputs` (adopters shouldn't edit code); add the new measurement to the
`ontology`; add the new pip dep to requirements.txt; **COPY the new module in the
Dockerfile** (see pitfall); CHANGELOG entry; README section; git tag `vX.Y.Z`.
Stage-5 (live node + real classifier plugin) is a separate deploy — defer it from
the code release.

## Two workflow pitfalls proven this session (general plugin lessons)

### Dockerfile per-file COPY trap
sage-yolo2's Dockerfile `COPY`s each source module individually
(`COPY consumer.py .`, `COPY app.py .`, …) rather than `COPY . .`. When you add a
NEW module (e.g. `crop_writer.py`), it is silently omitted from the image → the
container crashes at startup with ImportError, invisible to `make test` (which
runs from the repo, not the image). ALWAYS add a matching `COPY <newmodule>.py .`
line when introducing a new top-level module to such a repo; grep the Dockerfile
for the new filename as a build gate.

### Shared sys.modules stub fragility across test files
Multiple test files stub the heavy stack (cv2, torch, ultralytics, waggle) into
`sys.modules` before `import app`. Because `sys.modules` is shared across the
pytest session and `app` binds ONE `cv2` object at first import, whichever test
file imports `app` first fixes the cv2 stub for all of them. A stub that only sets
what ITS tests need (e.g. omits `imencode`, or gives an `imread` incompatible with
another file's expectation) makes the suite PASS OR FAIL BY FILE ORDER. Fix: make
every file's stub agree on the shared surface (set the union of needed attrs, with
compatible behavior), and verify by running the app-importing test files in BOTH
orders, not just the default `make test` order.
