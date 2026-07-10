# Detect-then-Classify Vision Pipelines on Sage (YOLO → crop → BioCLIP)

Design pattern for combining a **detector** (YOLO) with a **zero-shot
classifier** (BioCLIP) on Sage edge nodes. Applies whenever a whole-image
classifier is producing low-quality calls on small subjects or empty frames.

Full design note (committed, DRAFT for review, no impl yet):
`~/AI-projects/sage-bioclip/BioClip-Yolo-Design.md` (sage-bioclip repo, commit
fd45719). Read that for the complete staged plan + open questions. This is the
condensed rationale so future sessions don't re-derive it.

## Why detect-then-classify (the core insight)

BioCLIP is a **whole-image zero-shot classifier** with **no reject class** — it
always returns *some* taxon, even on an empty feeder frame. Two failure modes in
production:
1. **No reject class** → confident-but-wrong calls on empty frames. Current
   band-aid: raise `--min-confidence` to ~0.7, which also discards real
   low-confidence birds.
2. **Background dominates small subjects** → a hummingbird at 2% of a 1080p
   frame becomes a smudge after BioCLIP resizes the whole frame to 224×224; the
   embedding mostly describes leaves/sky.

Fix = the standard CV pattern: **localize first, classify second.** YOLO finds
*where* the animal is (bbox), crop to it, then BioCLIP classifies a tight image
that is almost entirely the subject. YOLO effectively becomes the reject class
BioCLIP lacks ("no detection → nothing to classify").

## Feasibility (grounded in the actual plugin code)

- `YOLODetector.detect(frame_bgr, target_classes)` already returns
  `[{class, confidence, bbox:[x1,y1,x2,y2]}, ...]` — integer pixel xyxy boxes.
- `BioCLIP2Classifier.classify(pil_image, top_k)` accepts **any** PIL image, so
  handing it a crop instead of the whole frame is a one-line call-site change.
- The only genuinely new code is a `crop_bbox` helper (outward padding ~10%,
  clamp to frame bounds, skip crops smaller than ~32px).

So the glue is small: `capture → yolo.detect → for each det: crop → bioclip.classify → fuse → publish/annotate`.

## Key design decisions (from the note)

- **New plugin** (`sage-detect-classify`), not a modification of the
  in-production sage-yolo / sage-bioclip plugins (keeps their resource profiles
  legible and avoids pulling the ~28GB BioCLIP model into the YOLO image).
- **Per-stage on/off toggles** `--detect`/`--classify` give a 4-mode matrix that
  doubles as a parity test plan vs the existing single-stage plugins.
- **New topic namespace** `env.detection.object.*` for fused per-object records
  (do NOT overload whole-image `env.species.*` — same lesson as the timing-units
  topic-collision rule).
- **Split telemetry**: `plugin.duration.inference.detect` vs `.classify` — never
  reuse the single `plugin.duration.inference` topic with two meanings.

## Pitfalls that will bite

- **Dual-model VRAM**: YOLO11x ~4-5GB + BioCLIP 2.5 ViT-H ~28GB. Fits Thor's
  128GB unified, but will NOT co-reside on small nodes (Xavier NX) — fail-fast on
  low VRAM, don't OOM mid-cycle.
- **COCO has no insect class** (and only one generic "bird"). So this pipeline
  helps birds/mammals but is nearly useless as a gate for insects — run insect
  monitoring as whole-frame (`--no-detect`). Real scope boundary, not a knob.
- **YOLO-miss recall cliff**: if YOLO misses the fast/tiny hummingbird there's no
  crop and no species call — the exact thing whole-image *did* catch. Keep an
  optional `--fallback-whole-frame` for recall-critical deployments.
- Meta must be str→str (pywaggle) — `str()` every value (the birdnet float-meta
  crash lesson applies here too).
- Coordinate traps: xyxy vs xywh, BGR vs RGB, padding clamp, normalized-vs-pixel
  bbox — unit-test each on a synthetic frame.

## Future: three-stage YOLO → SAM → BioCLIP

Deferred (adds a 3rd large model). SAM turns the YOLO box into a pixel-accurate
mask so BioCLIP classifies background-removed pixels. Design the v1 crop step as
a pluggable `--region-method {box,sam}` seam so SAM slots in later without a
rewrite. Measure whether plain box-crop already gets BioCLIP most of the way
(crop-vs-whole-frame confidence study) before paying for SAM.
