# Decoupling "publish topic" from "save media" in inference plugins

A recurring design need for Sage inference plugins (bioclip, birdnet, yolo, and
any future model plugin): the two things a plugin does with a detection have very
different cost profiles and should be controlled by separate knobs.

- **Publishing a topic** is cheap (bytes of metadata per detection).
- **Saving input media** (image/audio clip upload to Beehive) is expensive — tens
  to hundreds of KB per artifact. On edge nodes, upload bandwidth + Beehive
  storage are the real constraint, NOT inference compute.

A single `--min-confidence` threshold that gates BOTH publish and save is a blunt
proxy. A student studying Barn Owls does not want the bucket full of
high-confidence Robin images. The fix is two independent parameters.

## The two-parameter model (agreed convention)

| Parameter | Governs | Semantics |
|-----------|---------|-----------|
| `--min-confidence` | **Publish** | Floor for emitting a topic at all. Raise it to reduce noisy topic reports. Does NOT save media. |
| `--save-match` | **Save** | OR-list of `name:confidence` rules. ANY match → upload the clip/frame once. Only path that saves input media. |

### `--save-match` format (decided)
Single delimited string so the exact save logic is visible verbatim in logs/job
spec — no reconstruction from repeated flags:

```
--save-match "Barn Owl:0.5,Cardinal:0.7"
```
- `,` separates rules; `:` separates name from confidence.
- `*:0.7` wildcard = save any detection ≥ 0.7 (reproduces legacy simple-threshold
  behavior).

### Matching rule (decided)
- **Case-insensitive EXACT match** on the detection's **common name OR scientific
  name**, at the rank the plugin is publishing. `*` is the only wildcard.
- NO substring matching (rejected as a footgun — "Cardinal" must not silently
  also match "Northern Cardinal"; the student writes the exact emitted name).
- **Rank-aware, document prominently:** the name matches against whatever rank the
  plugin publishes (bioclip `--rank Order` → match "Lepidoptera", not species).
  A species rule on an order-rank job silently never fires — must be documented.

### Multiple detections per execution (decided)
Models often return several detections per input (one 30s BirdNET clip → 4
detections; YOLO → many boxes). Evaluate save rules across ALL detections: ANY
match (OR over rules × detections) saves the WHOLE clip/frame ONCE. Exactly one
artifact per execution, never one-per-detection.

## Periodic reference sampling → SEPARATE plugin (decided)
Do NOT embed "save one every hour" inside an inference plugin. It clashes with the
continuous-vs-windowed lifecycle (a windowed GPU pod only lives ~5 min and can't
do "once an hour"). Instead make a dedicated **sampler** plugin:
- Wall-clock schedule (e.g. hourly) via SES science rule.
- NO inference, NO GPU → schedules freely without contending for the single Thor
  GPU the AI pipeline uses.
- Uploads tagged `meta={"trigger":"periodic-sampler"}`, distinct from
  match-triggered saves. Period change = one-line schedule edit, never touches the
  scientific pipeline.

## Hard invariants (audit each plugin for these)
1. **Publish always; save selectively.** Every execution publishes its topics
   (per-detection + always-on summary/heartbeat) regardless of `--save-match`.
   Only the upload is gated. The two code paths must be unmistakably separate.
2. **Every execution emits datapoints even with ZERO detections** (summary with
   total_detections=0 is the liveness signal). LATENT BUG PATTERN seen in birdnet:
   the summary `plugin.publish` was nested inside `if detections:`, so quiet cycles
   published nothing — looked identical to "job dead." Hoist the summary/heartbeat
   publish OUT of the detection branch. Check this in every plugin.
3. `--save-match` is the SOLE media-save path. No other code path uploads media.
4. ECR description must state plainly: every run produces a few datapoints even
   with no detections; `--save-match` is the only thing that keeps input samples;
   `--min-confidence` only affects topic reporting noise.

## OPEN questions (unresolved as of 2026-06-23 — revisit before coding)
- **Per-species save threshold vs global publish floor.** If `--save-match
  "Barn Owl:0.5"` but `--min-confidence 0.7`, a 0.55 Barn Owl is never published —
  can it still be saved? Model (A): save-list operates only on PUBLISHED detections
  (one floor, simple; save thresholds effectively can't go below the floor).
  Model (B): save-list rescues sub-floor detections for upload (evaluate against
  raw model output; you can then have a saved artifact with no published topic at
  that confidence). Leaning (A) for the clean mental model — Pete to decide.
- **Annotated vs raw media** on save (bioclip/yolo currently upload annotated).
- **YOLO name space**: COCO class names only ("bird","person","car"), no
  scientific name — the "common OR scientific" rule degrades to class name; doc
  per-plugin what's matchable.
- **Default when `--save-match` omitted**: save nothing (pure publish-only) vs
  default `*:<min-confidence>` for legacy mimicry. Decide explicitly.

## Where the working draft lives
Full design note (with decision log): `sage-bioclip/docs/DESIGN-save-match-and-sampling.md`
— this is the cross-plugin spec; mirror final behavior into each plugin's ECR
science description.
