# Detect → crop → classify cascade (cache-mediated, no cross-plugin calls)

A reusable two-stage vision pipeline where a detector plugin produces cropped
images into a SECOND cache stream, and a downstream classifier consumes those
crops. Built for sage-yolo2 (crop producer) + sage-bioclip2 (crop consumer) on
H00F. The stages never call each other — the shared local-cache is the only
coupling.

```
image-sampler2      sage-yolo2 (detect + CROP)            sage-bioclip2 (classify)
 camera → cache  →   YOLO detects, crops each detection →  read crops, BioCLIP2 species
 <cam>/top           → <cam>-crops/<cam>-crop-<idx>/        → env.species.* + provenance
```

## Design decisions that made it clean (reuse these)

- **The crop stream is its own cache** (`<crop-cache-name>/<camera>-crop-<idx>/`),
  one bounded ring PER detection index, so N objects in a frame → N distinct
  entries. Own `--crop-max-count/--crop-max-mb` caps, separate from the raw cache.
- **Producer feature is OFF by default.** A separate `--crop-match "class:conf"`
  flag (same grammar as `--save-match`) gates it; empty = no behaviour change.
  Crop at a slightly HIGHER conf than save (crops feed a classifier — only crop
  what you're fairly sure of).
- **Crops are the SAME v2 frame format** as raw frames (EXIF + UserComment JSON).
  Because of this, the classifier's cache dir is a single `--input` parameter and
  the full-frame-vs-crop switch is CONFIG-ONLY, no code branch:
    `--input /local-cache/<cam>/top`              # full frames
    `--input /local-cache/<cam>-crops/top-crop-0` # only the crops
- **Crop inherits the parent frame's capture_ts** → species stays frame-anchored
  (traces to when the photo was taken, not when inference ran).
- **Provenance rides along**: the crop's UserComment carries a nested `source{}`
  block (source_class / source_confidence / source_bbox / source_unique_id /
  detection_index). The classifier reads it and attaches source_* to the species
  record → a species result traces back through the detection to the parent frame
  and bbox. Harmless no-op on plain frames (no `source` key → full-frame mode).
- **Padding + min-px floor** on crops: `--crop-padding 0.15` (classifiers like a
  little context), `--crop-min-px 32` (skip sub-N-px boxes; never upscale garbage).
- **Publish a count** (`env.crop.count`) frame-anchored when ≥1 crop is written.

## Building the second plugin = assembly, not invention

sage-bioclip2 was built as: **existing model brains (v1 plugin) grafted onto the
proven cache-consumer skeleton (the other v2 plugin).** Concretely:
- **Vendor the read-side machinery BYTE-IDENTICAL** across the plugin family:
  `consumer.py` (scan/parse/metadata/identity), `selection.py` (stride/all-unseen),
  `seenstore.py` (dedup), `node_info.py`, `save_match.py`. sha256-verify after copy.
  These ARE the v2 read contract; document in VENDORED.md with a sync obligation
  and let the carried-over tests be the drift guard. (After 2+ consumers exist, a
  shared package is the cleaner long-term move than repeated vendoring — track as a
  follow-up, don't block on it.)
- **Graft the model class** from the v1 plugin (e.g. BioCLIP2Classifier wrapping
  pybioclip TreeOfLifeClassifier) + its publish shape (env.species.*).
- The only genuinely new code: swap detector→classifier in the wake loop, and a
  small helper to read `source{}` provenance off each crop.

## Ring-sizing rule (producer/consumer rate)

The classifier must DRAIN the crop cache faster than the detector FILLS it, or
crops evict (oldest-first) before they're classified. Same rule as the raw cache.
Tune `--every` on the consumer and the crop ring caps together once live; leave
generous defaults (500/500) until the real drain cadence is known.

## Verify the cascade live (data-plane, not just logs)

Query the data API for the classifier's topic and confirm the provenance meta is
present — that proves the whole chain:
```
curl -s -X POST https://data.sagecontinuum.org/api/v1/query \
  -H 'Content-Type: application/json' \
  -d '{"start":"-30m","filter":{"vsn":"H00F","name":"env.species.species"}}'
# expect: value=<taxon>, meta.plugin=...:<ver>, meta.camera=<cam>-crop-0,
#         meta.source_class=<detector class>, meta.source_unique_id=<parent crop sha>
```
Data API cloud propagation can lag a few minutes; logs (`Published env.species...`)
confirm the publish happened before the query catches up.

## Pitfalls

- **A non-idempotent build-time patch imported at runtime.** e.g.
  `patch_pybioclip.py` asserts the pristine library source, so it must run ONCE at
  Docker build time only. An `import patch_pybioclip` in the plugin's model-load
  path re-runs it and crashes on the node. Apply such patches in the Dockerfile;
  never import them at runtime. (Check how the reference/v1 plugin does it before
  copying — v1 relied solely on the build-time patch.)
- **Forgetting to COPY a vendored module in the Dockerfile.** The plugin COPYs each
  .py individually; a newly added module (e.g. crop_writer.py) missing from the
  COPY list = runtime ImportError in the image. Grep the Dockerfile COPY lines
  against the module list before building.
- **Looking for crops in the wrong dir.** Crops land in a SIBLING top-level cache
  dir (`<cam>-crops/`), not inside the raw `<cam>/` tree, and are root-owned — a
  non-sudo `ls` of the raw dir shows nothing. `sudo find <root>/<cam>-crops`.
- **Low-confidence non-target crops.** A zero-reject classifier will label partial/
  edge crops as something (e.g. a rabbit at 70% on a bird-crop stream). Tighten
  with the consumer's `--min-confidence` or the producer's `--crop-match` threshold.
