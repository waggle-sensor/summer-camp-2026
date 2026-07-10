# Vision plugin gotchas: image annotation + classifier confidence

Lessons from the bioclip-species-classifier plugin (BioCLIP 2.5 ViT-H/14)
that apply to any Sage camera/vision plugin that draws text on frames or
publishes a classifier confidence.

## 1. OpenCV multi-line text overlap — derive line spacing from MEASURED glyph height

Symptom: annotated images have text lines that overlap/touch vertically;
each line is partially obscured by the one below.

Root cause: line spacing computed from a fixed constant times the font
scale, e.g. `line_gap = int(30 * scale)`. That constant is unrelated to the
actual rendered glyph box, so at common scales the gap is SMALLER than the
text height + baseline + background-box padding. Measured collisions with
the old `30*scale` formula (FONT_HERSHEY_SIMPLEX):

| resolution | old line_gap | text box height | result        |
|------------|--------------|-----------------|---------------|
| 3840x2160  | 64px         | 72px            | 8px OVERLAP   |
| 1920x1080  | 32px         | 39px            | 7px OVERLAP   |
| 640x360    | 15px         | 21px            | 6px OVERLAP   |

Fix: measure a representative glyph once with `cv2.getTextSize` and set the
line gap from text-height + baseline + padding, so clearance is always
positive at any scale:

```python
font = cv2.FONT_HERSHEY_SIMPLEX
scale = max(0.5, min(w, h) / 1000.0)
thickness = max(1, int(scale * 2))
(_, sample_th), sample_base = cv2.getTextSize("Ag", font, scale, thickness)
line_gap = sample_th + sample_base + max(6, int(sample_th * 0.5))
```

Same fix verified positive clearance: 19px @ 4K, 8px @ 1080p, 2px @ 640x360.
Use a single `draw_line(text, y)` helper that draws the background rectangle
sized from `getTextSize` of THAT line (incl. baseline) and advances `y` by
`line_gap` — don't duplicate near-identical draw blocks.

Verification without a working vision tool: you can PROVE non-overlap
numerically by computing `line_gap - (text_h + base + pad)` per resolution
and asserting it is > 0; no need to eyeball the rendered image.

## 2. BioCLIP confidence is NOT detection — whole-image classifier, no reject class

Symptom: object store has annotated frames labeled e.g. "Archilochus
colubris 99-100%" with NO bird actually in the frame (empty feeder, green
foliage).

This is NOT a code/scoring bug. Verified empirically: pybioclip scores are
real softmax probabilities (0-1), sorted descending, read correctly. An
EMPTY-feeder ground-truth image scored Archilochus colubris at 1.0000; a
green foliage live frame (4.7% red pixels, no bird) scored it 0.9999.

Mechanism: BioCLIP is a whole-IMAGE zero-shot classifier over ~450K species
with NO "nothing here" class. Softmax must sum to 1 across species, so on a
low-information frame it collapses almost all mass onto the single closest
embedding -> a confident, peaked, but meaningless prediction. The red
hummingbird feeder is itself a near-perfect cue for Ruby-throated, because
the model saw many training images of that species near feeders.

Consequences for plugin design:
- A high BioCLIP confidence is NOT evidence the organism is present.
- Confidence-margin / entropy gating does NOT catch this: the margin is
  huge (1.0000 vs 0.0000), the distribution is sharply peaked.
- Lower-resolution frames INFLATE confidence (less competing detail), so
  the same scene can score 28% at full res and ~100% at 640x360.

The correct fix is a DETECTOR gate, not an in-plugin classifier threshold:
gate BioCLIP behind an object detector that knows whether a bird-shaped
object is present (YOLO `env.count.bird > 0`). Keep this at the SYSTEM level
(the slack-hummingbird watcher), not inside the classifier plugin —
respects "one plugin per model" and avoids bloating the image with a second
model. The plugin itself can still publish/annotate honestly; presence is
established downstream.

## 3. Scope fixes the way the user asks — don't bundle unrequested changes

When the user asks for one specific fix (e.g. "fix the text overlap"),
ship ONLY that, even if you've identified a second real issue in the same
function. This session: the user explicitly said to fix the text-overlap
line spacing and "skip the other fix (confidence/annotation wording) for
now." The right move was to revert the honest-annotation wording changes
and keep the annotation labels/behavior byte-for-byte original, changing
only the line-gap math. Pete prefers tight, minimal diffs scoped to the
stated ask; flag the other issue for a separate decision rather than
folding it in. (The confidence/false-positive work is parked for the
watcher redesign, not the classifier plugin.)
