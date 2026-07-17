# Standard `plugin.duration.*` performance telemetry

Sage plugins on production/TAFT nodes publish per-phase timing metrics. This is a
de-facto convention (avian-diversity-monitoring, cloud-cover, water-depth, etc.)
— add it to any inference plugin you build. It makes cold-start cost and
per-cycle latency observable from the data plane, and doubles as a liveness
signal even when the science output is empty/below threshold.

## The three standard topics

| Topic | Frequency | Wraps |
|-------|-----------|-------|
| `plugin.duration.loadmodel`  | once, at startup | model construction / load to device |
| `plugin.duration.input`      | per cycle        | acquiring input (camera snapshot / audio capture) + decode |
| `plugin.duration.inference`  | per cycle        | the classify/detect call |

Values are **nanoseconds**, published as integers. Production sanity values:
inference ~5.4e9 (5.4s, BirdNET CPU), model load ~12–43e9 (12–43s), input
~13–19e9. Query with `sage_data_client` filter `name: "plugin.duration.*"`.

Note the spelling: the canonical phase is **`inference`** (avian-diversity-
monitoring, TAFT). The water-depth plugin used `inferencing` — prefer `inference`
to match the dominant convention and keep cross-plugin queries clean.

> Related reference: **`pywaggle-upload-naming-and-timestamps.md`** covers the
> other half of the pywaggle mechanism — how `upload_file` names objects
> (`{timestamp}-{filename}`), what metadata is plugin-side vs server-injected,
> RTSP `sample.timestamp` semantics (grab time, not exposure time), and the
> two-timestamp capture+upload pattern for batch-and-hold.

## The mechanism — `plugin.timeit` (don't hand-roll time math)

pywaggle exposes a context manager that times the block and **auto-publishes**
the duration. Verified in pywaggle source (`src/waggle/plugin/plugin.py`):

```python
@contextmanager
def timeit(self, name):
    start = timeit_perf_counter()        # perf_counter_ns
    yield
    finish = timeit_perf_counter()
    duration = timeit_perf_counter_duration(start, finish)  # nanoseconds
    self.publish(name, duration)         # auto-publish, no timestamp arg
```

So you just write:

```python
with plugin.timeit("plugin.duration.loadmodel"):
    model = load_model()
```

No manual `time.time_ns()`, no explicit `plugin.publish` for the duration — the
context manager does it. It uses publish-time default timestamp (matches how
production records look).

## The refactor pattern (the non-obvious part)

Plugins typically build the model in the classifier/detector `__init__`, which
runs BEFORE `with Plugin()` opens — so you can't time it there. Fix: split
construction from loading.

```python
class MyClassifier:
    def __init__(self, ...):
        ...                 # cheap: just store config
        self.model = None   # not loaded yet

    def load(self):         # heavy work here, callable inside Plugin context
        self.model = build_model(...)

# main():
clf = MyClassifier(...)             # cheap, before Plugin
with Plugin() as plugin:
    with plugin.timeit("plugin.duration.loadmodel"):
        clf.load()                  # now timed
    while True:
        with plugin.timeit("plugin.duration.input"):
            frame = grab_input()
        with plugin.timeit("plugin.duration.inference"):
            preds = clf.classify(frame)
        ... confidence gate / publish science output ...
```

### Pitfalls
- **Publish input/inference EVERY cycle, BEFORE the confidence gate.** If you
  only time inside the "something was detected" branch, you lose telemetry on
  empty/low-confidence cycles — which is exactly when you most want to know the
  plugin is alive and how long it's taking. (This was the gap that left an
  insect-cam window publishing nothing with no way to tell load-vs-inference.)
- **Pyright will warn** `"... is not a known attribute of None"` after the
  split (model is None until load()). Harmless — load() always runs first.
- **Dry-run / no-Plugin paths**: call `load()` untimed (there's no plugin to
  publish to). Guard with `if plugin is not None:` around the `timeit` blocks.
- Confirm `plugin.timeit` exists in the image's pywaggle (it has for years; it's
  in `waggle/plugin/plugin.py`). Don't reinvent with manual ns math.
- **THE BIG ONE — the deferred-`load()` refactor can crash-loop in production,
  and Pyright warns you first.** When you split construction from loading, the
  new `load()` method must still have access to everything `__init__` did:
  module-level imports (esp. *lazy* `import birdnet` inside the function/file),
  reconstructed locals (`lat, lon, week = self.lat, self.lon, self.week`), and
  `self.*` config. If anything the moved code referenced is now out of scope, the
  plugin raises AT STARTUP inside the Plugin context → the pod dies immediately →
  the scheduler relaunches it every ~10s → a silent **crash-loop** that publishes
  ZERO records (no science output AND no telemetry, so it looks identical to "no
  detections"). In one session birdnet 0.1.5 did exactly this. Pyright had
  flagged `"birdnet" is not defined` / `"... is not a known attribute of None"`
  in the refactored `load()` — these were dismissed as "lazy-import false
  positives" but were the actual runtime bug. **Lesson: after a load() refactor,
  treat Pyright name/scope warnings in the moved code as real until proven
  otherwise, and run the entrypoint once (even just `python3 app.py --help` or a
  dry-run that calls `load()`) before building the 20–28 GB image.**

## MANDATORY post-deploy verification (don't declare success on "Submitted")
SES reporting a job `Running` / `Submitted` does NOT mean the plugin works — a
crash-looping pod also shows as Running while its container dies and restarts.
After resubmitting at a new version, VERIFY from the data plane within a few min:

1. Check `sys.scheduler.status.plugin.launched` for the job — if you see the SAME
   job's pod instance ID changing every ~10s (e.g. `birdnet-species-RIFi4D`,
   `-Tn9XHP`, `-riRu7C` ... new suffix each tick), that's a CRASH-LOOP, not
   healthy continuous operation.
2. Confirm the expected topics actually appear (the science topic AND
   `plugin.duration.*`). Zero `plugin.duration.loadmodel` after startup = the
   plugin never got past model load = almost certainly crashing.
3. Only then call it deployed. If crash-looping: get pod logs
   (`sudo kubectl logs -n ses <pod> [--previous]`) to see the traceback — but
   pods churn fast, so retry the log grab in a loop, or roll back to the
   last-good version (it's still sideloaded) while you fix forward.

## Querying + plotting the telemetry from the data plane (consumer side)

You don't need `sage_data_client` installed to pull this — the raw HTTP query API
works from a plain stdlib script (handy in sandboxes without the client):

```python
import json, urllib.request
def query(name, vsn="H00F", start="-24h"):
    body={"start":start,"filter":{"vsn":vsn,"name":name}}
    req=urllib.request.Request("https://data.sagecontinuum.org/api/v1/query",
        data=json.dumps(body).encode(),headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req,timeout=90) as r:
        return [json.loads(l) for l in r.read().decode().splitlines() if l.strip()]
```

Response is **NDJSON** (one JSON object per line, not a JSON array) — split on
newlines and parse each line. Each record: `{"timestamp","name","value","meta":{...}}`.

- **Group series by `meta.plugin`** — the plugin tag is the full ECR ref
  `registry.sagecontinuum.org/<ns>/<name>:<version>` (e.g.
  `.../yolo-object-counter:0.3.0`). That's your join/legend key; shorten it for
  labels. The SAME node runs yolo+birdnet+bioclip, so filtering by `name` alone
  returns all three interleaved — you MUST split on `meta.plugin`.
- **Convert ns→ms for humans**: `value/1e6` (ns→ms) or `/1e9` (ns→s). Records are
  native integer nanoseconds. State the conversion in the axis label.
- **Sample counts differ per phase**: `inference`/`input` are per-cycle (hundreds
  in 24h); `loadmodel` fires once per job (re)start, so a windowed/self-exit job
  shows N loadmodel samples = N GPU-window entries over the period. Plot each
  series against its OWN sample index (0..len-1), not a shared X.
- **USE LOG-Y when mixing plugins.** Real 24h range spans ~22 ms (yolo inference)
  to ~10,400 ms (bioclip ~28GB loadmodel) — nearly 3 orders of magnitude. On a
  linear Y the big series flatten everything else to the floor. Produce a log-Y
  version for reading all series together (offer a linear one too if asked).
- Plotting needs matplotlib, which isn't in the execute_code sandbox and the host
  Python is PEP-668 externally-managed → make a venv:
  `python3 -m venv ~/AI-projects/.plotvenv && ~/AI-projects/.plotvenv/bin/pip install matplotlib`,
  then run the plot script with that interpreter. Reusable script:
  `scripts/query-and-plot-durations.py`.
- Convention for 6-series (3 plugins × 2 phases): distinct hue per plugin,
  solid line = inference, dashed = loadmodel; 6 distinct colors total.

## What the three timers do NOT measure (gap analysis for consumers)

`input + inference` are sequential non-overlapping `with` blocks (siblings, not
nested); `loadmodel` is one-time outside the loop. Total GPU-hold ≈
`loadmodel + N×(input + inference + overhead)`. But a cycle's true wall-clock has
untimed costs living in the gaps — know these when reasoning about throughput or
cycle accounting:
1. **Post-processing / publish / upload is untimed** — after `inference` closes:
   count aggregation, `plugin.publish(...)`, and on a save-match hit `draw_boxes`
   + `cv2.imwrite` + `plugin.upload_file`. The object-store upload can be slow
   (cross-country ~2min propagation) and is completely invisible to the timers.
2. **Inter-cycle `time.sleep(interval)`** — idle, deliberately uncounted, so
   wall-clock cycle period ≠ input+inference.
3. **Crop/pre-processing between input and inference** — negligible today, but in
   a YOLO→crop→BioCLIP pipeline the crop+BGR→PIL lands in the untimed gap unless
   you split inference into `inference.detect` + `inference.classify`.
4. **First-inference CUDA warmup** is folded into cycle-1's `inference` and
   inflates it — discard cycle 1 before averaging steady-state.
5. **loadmodel scope depends on lazy loading** — frameworks that defer weight
   load / CUDA-context creation to the first forward pass leak that cost into
   cycle-1 `inference` instead of `loadmodel`.
6. **Model download** (HF Hub pull) hides in `loadmodel` on a cold image; ~zero on
   sideloaded images with baked-in weights.
7. **Pod schedule + image pull + interpreter start** (SES "submitted" → process
   reaching `loadmodel`) is outside all three and outside the plugin entirely.

To close cycle accounting the two worth adding are a **publish/upload timer** and
a **detect-vs-classify inference split**.

## Why this matters operationally
These three numbers turn GPU-window sizing (e.g. tuning `--max-runtime` for the
windowed GPU-sharing scheme) into a data-driven decision: read
`plugin.duration.loadmodel` and you know precisely how much of a bounded window
the cold start eats vs. real inference — no guessing from indirect signals.
For a ~28 GB model (BioCLIP 2.5) the cold start can dominate a short window.

Applied 2026-06-23 to yolo 0.2.2, bioclip 0.3.3, and birdnet (0.1.5 crash-looped
on the import-scope bug above → fixed in **0.1.6**). All four jobs (yolo-5661,
bioclip-5662, insect-5664, birdnet-5665) VERIFIED in the data plane emitting
`plugin.duration.{loadmodel,input,inference}` at the new tags. Real birdnet
numbers from 0.1.6: loadmodel ~2.4s, input ~31–34s (30s audio capture dominates),
inference ~2.7s. The crash-loop took ~5 verification rounds to diagnose because
SES pods churn fast and show "Running"; the deterministic fix was to run the
sideloaded image directly on the node (`sudo docker run --rm --runtime=nvidia
--network host <tag> <exact job args>`) which reproduces startup/load/capture
without chasing ephemeral pod logs.
