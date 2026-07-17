# Mapping the Sage plugin/WES stack as an intertwined constellation

When Pete asks to "map how the pieces are *supposed* to relate — what's missing, not
yet implemented, not yet tested" across several repos (e.g. sage-yolo, sage-bioclip,
wes-local-cache-manager, image-sampler2, pywaggle2, wes-nodeinfo-injection), the
deliverable is a BIG-PICTURE synthesis, not a per-repo status. Write it to a loose
`~/AI-projects/SAGE-STACK-MAP.md` (living reference). This is a recurring class of
task; do the legwork on ground truth, don't map from memory.

## Method (ground-truth first, in parallel)
1. Inventory every named repo: `git describe --tags`, HEAD, doc list. Confirm each
   exists (some may live outside `~/AI-projects`).
2. For the ML/consumer plugins, the load-bearing questions are:
   - Do they READ `/local-cache` (consumer) or open their OWN camera/RTSP/`--image-dir`?
     `grep -riE "local-cache|read_cache|from-cache|image-sampler|camera_stream"`.
   - Do they call `get_node_info()` / geotag / carry VSN+GPS? (`grep -niE
     "get_node_info|WAGGLE_NODE|nodemeta|geotag|vsn"` — often ZERO in yolo/bioclip).
   - Do they upload, and is upload default or a test path? (`grep -c upload_file`).
3. Read the design docs for INTENDED relationships that may not be built:
   `BioClip-Yolo-Design.md` describes a detect-then-classify pipeline; the plugin
   `overview.md`/`readiness-gap.txt` state the producer/consumer intent.

## The layered model (WES components vs user plugins)
- **WES platform layer (system pods):** wes-nodeinfo-injection (identity env into
  every pod), wes-local-cache-manager (bounds `/local-cache`). These are CI/upstream
  deliverables.
- **User-plugin layer (scheduled jobs):** image-sampler2 (PRODUCER → cache),
  sage-yolo + sage-bioclip (intended CONSUMERS).
- **pywaggle2 = the shared client library** all plugins call. NOT one repo — slices:
  node-info reader ✅ (pywaggle2-nodeinfo), cache primitive 🟡 (trapped in
  image-sampler2/cache.py, not yet a callable consumer API), acquisition ladder 🔴
  (design-only, pywaggle2-design.md §1).

## Two data-flow models — DO NOT conflate
1. **Cache producer/consumer:** image-sampler2 fills `/local-cache`; yolo/bioclip are
   *meant* to read it instead of each opening the camera.
2. **In-process detect-then-classify:** one fused plugin — YOLO detects+crops →
   BioCLIP classifies each crop → one fused record. Design note verified both wrappers
   already expose the right interfaces (`YOLODetector.detect()→boxes`;
   `BioCLIP2Classifier.classify(pil)→names`); the only new code is `crop_bbox` + glue.

## Key durable finding (state as of 2026-07): the architecture is HALF-BUILT
- image-sampler2 PRODUCES to cache ✅, geotags via nodemeta ✅, upload is a test path.
- **yolo/bioclip are consumers in NAME ONLY** — they still open their own cameras, do
  NOT read the cache, and publish counts/species with ZERO location metadata (no
  `get_node_info()` call, though the reader is done + verified).
- The fused YOLO→BioCLIP pipeline is DESIGN-ONLY (no combined plugin / `crop_bbox`).
- The cache primitive has never been extracted from image-sampler2/cache.py into a
  library API the ML plugins can call.

## Critical path (what unlocks the most, in order)
1. CI provisions `/local-cache` + deploys the manager → image-sampler2 stops falling
   back to pod-private `/tmp`. SINGLE BIGGEST UNLOCK; everything downstream is inert
   without it (this is readiness-gap BLOCKER 1).
2. Extract the pywaggle2 cache-consumer API; wire it into yolo/bioclip.
3. Wire `get_node_info()` into yolo/bioclip (cheap, high-value — reader already done).
4. Build the fused detect-then-classify pipeline.
5. Upstream merges (nodeinfo patches, pywaggle2 reader, `mobility` manifest field).

## Presentation shape Pete wanted
He suggested "maybe rows/columns too big — short paragraphs with sections." Deliver: a
one-picture ASCII architecture diagram, a per-piece block (feature summary / where it
goes / local-Thor use / what-CI-needs / waiting-on), a gaps table, the critical path,
and a ready-for-CI-vs-still-ours split. Use ✅/🟡/🔴/⬛ status glyphs.
