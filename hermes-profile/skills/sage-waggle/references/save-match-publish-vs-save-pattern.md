# Decoupling "publish" from "save" in Sage inference plugins (`--save-match`)

A reusable architectural pattern for any Sage plugin that runs a model and
both PUBLISHES detections (cheap topics) and SAVES input media (expensive
image/audio uploads). Proven first in bioclip-species-classifier 0.4.0;
intended to be replicated identically into birdnet and yolo. Full design note
lives in the plugin repo: `docs/DESIGN-save-match-and-sampling.md`.

## Why

A single `--min-confidence` historically did double duty: it gated BOTH what
got published AND whether the media was uploaded. Those have very different
costs — a topic is a few bytes; an image/audio upload is tens–hundreds of KB
and is the real edge constraint (bandwidth + Beehive storage). A confidence
threshold is a blunt proxy for "is this worth saving." Decouple them.

## The two-knob model

- **`--min-confidence`** = the REPORTING FLOOR. Minimum confidence for a
  detection to be PUBLISHED as a topic. Raise it to cut noisy reports. Does
  NOT control saving.
- **`--save-match`** = controls media SAVING, and is the ONLY path that saves
  media. An OR-list of `Name:confidence` rules, single comma-delimited string:
  `"Barn Owl:0.5,Northern Cardinal:0.7"`. Media is saved if ANY detection
  matches ANY rule. Wildcard `"*:0.7"` saves anything ≥0.7 (reproduces the old
  "save above threshold" behavior). Omit `--save-match` → save NOTHING
  (opt-in). Save-list operates ONLY on already-published detections (single
  floor; a rule threshold below `--min-confidence` can never fire).

## Locked semantics (so all plugins behave identically)

- Name match is **case-insensitive EXACT** against the common OR scientific
  name (bioclip/birdnet) at the **published rank**, or the **COCO class name**
  (yolo). NO substring matching ("Cardinal" does NOT match "Northern Cardinal").
- Match is rank-aware: a Species rule on an `--rank Order` job never matches —
  document this prominently in ECR or users silently get nothing.
- ANY (rule × detection) match → save the whole clip/frame ONCE (one artifact
  per execution, not per detection).
- `--save-match` saves the ANNOTATED output (vision); audio plugins save the
  captured clip. A future periodic "sampler" plugin saves RAW (separate, no-GPU,
  wall-clock cron — deferred; survey waggle-sensor imagesampler/audiosampler
  first).

## Two non-negotiable invariants

1. **Publish-always / save-selectively as STRICTLY SEPARATE code paths.** In the
   run loop: PATH 1 publishes per-detection topics for the published set; PATH 2
   computes `should_save(...)` and uploads only on a hit. Never gate the publish
   behind the save decision.
2. **Every run emits a heartbeat datapoint even with ZERO detections** (e.g.
   `env.species.summary` = `{published_count, top_confidence}`), so a user can
   confirm from the data plane that the plugin ran — distinguishes "running,
   nothing seen" from "job dead." NOTE: birdnet's existing
   `env.detection.audio.summary` is nested inside `if detections:` — that's a
   bug; hoist it out so quiet cycles still publish it.

## Implementation notes

- Shared helper `save_match.py` (`parse_save_match` + `should_save`,
  dependency-free) is COPIED identically into each plugin repo (they don't share
  a package). A refactor to one shared package is a tracked follow-up; until
  then, ANY change to the helper must be mirrored to all copies.
- **Fail fast** on a malformed `--save-match` at startup: parse it before the
  Plugin/model load, `logger.error(...)` + `raise SystemExit(2)`. A typo'd rule
  that silently saved nothing would waste an entire deployment. `parse_save_match`
  raises `SaveMatchError` on: missing `:confidence`, non-numeric or out-of-range
  confidence, empty name, stray commas.
- Grammar: split rules on `,`; split name/confidence on the LAST `:`
  (`rpartition`) so scientific names with spaces work and ':' edge cases are
  predictable; lowercase names for compare; `*` is the only wildcard.
- Carry BOTH name fields on each detection dict so matching works on common OR
  scientific (e.g. bioclip's `classify()` must keep `common_name`, not just the
  rank-level `name`).
- Dockerfile must `COPY save_match.py .` alongside `COPY app.py .`.
- Tests: `tests/test_save_match.py` runs both under pytest AND as a
  dependency-free `__main__` runner (`python3 tests/test_save_match.py`), since
  the node/dev box may not have pytest. 29 cases cover wildcard, exact
  common/scientific, no-substring, OR-over-rules, OR-over-detections, YOLO COCO
  names, and every fail-fast malformed-spec case.

## Per-plugin ECR doc requirements (write for the USER, same commit as code)

A "Saving Images/Audio: `--save-match`" section with the grammar, a real-taxa
worked example, the `*:conf` wildcard, a prominent rank-awareness warning, a
"operates on published detections only" warning, and a parameter table that
clearly separates `--min-confidence` (publish floor) from `--save-match` (the
sole save path). Update the sage.yaml input description for `save-match` too so
the portal form explains it. Use REAL taxa in examples (Northern Cardinal /
*Cardinalis cardinalis*, Barn Owl / *Tyto alba*) so they lift straight into docs.
Audience is "user," not "student."

## Migration when upgrading a job to a save-match version

Add `--save-match` to existing job YAMLs or they will publish topics but STOP
uploading media (opt-in default). `"*:<conf>"` preserves prior "save above
threshold" behavior; a species list saves selectively.
