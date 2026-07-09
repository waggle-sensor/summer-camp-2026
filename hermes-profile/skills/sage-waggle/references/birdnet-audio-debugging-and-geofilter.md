# BirdNET audio plugin: debugging "zero detections" + geo-filter sourcing

Hard-won from operating birdnet-species on Thor H00F with a Reolink RLC-811A
hummingcam (faint built-in mic, no gain control, 16 kHz sub-stream audio).
Governs HOW to debug a BirdNET plugin that runs cleanly but detects nothing.

## 0. FIRST suspect for "zero detections": a CRASH in publish (pywaggle meta must be strings)

Before blaming the threshold, confirm the plugin actually PUBLISHES. A pod can
classify birds correctly and then **crash inside `plugin.publish()`**, so
nothing ever reaches the data API. This silently looks identical to "no birds."

ROOT CAUSE found on H00F (birdnet 0.1.2): pywaggle requires every value in the
`meta=` dict to be a **string**. Passing floats raises at publish time. The
per-species publish passed `start_time_s`/`end_time_s` as floats →
`publish_detections()` threw at the `plugin.publish(...)` line; the summary
publish (no meta) survived, so the heartbeat looked fine while real detections
vanished.

```python
# WRONG — floats in meta crash publish:
meta={"common_name": det["common_name"], "start_time_s": det["start_time"]}
# RIGHT — stringify every meta value:
meta={"common_name": str(det["common_name"]), "start_time_s": str(det["start_time"])}
```

GENERAL pywaggle rule (applies to yolo, bioclip, ANY plugin): `meta` values
must be `str`. The published VALUE itself can be numeric (float/int) or a JSON
string; only `meta` is the string-only dict. Audit every `plugin.publish(...,
meta={...})` call for non-string meta values.

How this surfaced: the data API showed zero `env.detection.audio.*` records for
hours even after the threshold fix. Catching a live one-shot pod's logs showed
`Classified ... 2 detections` immediately followed by a Traceback at the
`plugin.publish` line. Lesson: "0 records in the data API" + "model logs
detections" == a publish-side crash, not a detection problem.

Catching a brief one-shot pod to read its logs (they exist only ~30–40s per
tick, then are GC'd): poll fast and grab logs the instant phase==Running.
```bash
for i in $(seq 1 120); do
  POD=$(sudo kubectl get pods -n ses | grep <plugin> | awk '{print $1}' | head -1)
  [ -n "$POD" ] && [ "$(sudo kubectl get pod -n ses $POD -o jsonpath='{.status.phase}')" = Running ] \
    && { sleep 10; sudo kubectl logs -n ses "$POD" | tail -40; break; }
  sleep 2
done
```
Use `ssh -o ServerAliveInterval=15 -o ServerAliveCountMax=4` for these watch
loops — a plain long-lived ssh drops with "client_loop: send disconnect: Broken
pipe" (exit 255) before the pod fires.

## 1. "Running but zero birds" is ALSO often the THRESHOLD, not the model

A BirdNET plugin can fire every cycle, capture audio, log no errors, and still
report zero detections — while a human clearly hears a bird in the recording.

Debug chain that proved the cause (do it in this order):
1. **Capture a clip a human can listen to** (see the listen-clip script below).
   If you hear a bird, the audio path works.
2. **Run that exact clip through BirdNET at the JOB threshold** (e.g. 0.60).
   `--dry-run` so it doesn't publish. Expect "0 detections above threshold".
3. **Re-run at a LOW threshold (0.05)**. If the bird now appears (e.g. House
   Sparrow ~0.40 peak), the model HEARS it — the deployed threshold is just too
   high for this mic/stream quality.

Conclusion pattern: faint mic + low-bandwidth sub-stream depress confidence
into the 0.3–0.4 range, so a 0.60 threshold filters out real birds. Fix =
lower `--min-confidence` (0.60 → ~0.35), NOT a model change.

Running a clip through the plugin image (one-shot; birdnet has NO `--continuous`
flag — it uses `--num-recordings 1 --interval 0`, the default):
```bash
sudo docker run --rm --entrypoint python3 -v $(pwd):/data \
  registry.sagecontinuum.org/beckman/birdnet-species:<ver> \
  /app/app.py --input /data/clip.wav --min-confidence 0.05 \
  --bandpass-fmax 8000 --dry-run
```

## 2. Volume GAIN does NOT improve BirdNET confidence — proven, drop the idea

Tested same clip vs a +20 dB amplified copy through BirdNET. Confidence was
identical within ±0.01 (House Sparrow 0.3977 vs 0.3947), occasionally marginally
LOWER. BirdNET classifies on the time–frequency PATTERN, not absolute loudness;
uniform amplitude scaling adds no information. So a downstream `--gain` feature
is a DEAD END for detection. (It is still useful for HUMAN listening — keep gain
only in the listen-clip tool, never as a plugin detection lever.)

The real levers that DO help confidence:
- Lower the threshold (most effective — model already hears the bird).
- Use the camera MAIN stream if it carries higher-sample-rate audio than the
  16 kHz sub-stream (8 kHz Nyquist cuts upper harmonics that distinguish
  species). Worth checking before assuming the mic is the ceiling.
- Enable geo-filtering (removes implausible high-scoring noise — see §4).

Audio level sanity check (ffmpeg volumedetect): mean ~-27 dB with max 0.0 dB =
mostly quiet with occasional full-scale spikes (faint mic + transients). 0.0 dB
max can indicate clipping/DC offset — note it, but it is NOT why detection fails
(the threshold is).

## 3. The listen-clip workflow (reusable debugging tool)

Reolink FLV/BCS needs QUERY-PARAM auth (`&user=&password=`), NOT basic auth.
Capture with the SAME ffmpeg path the plugin uses so the clip == what BirdNET
hears: `ffmpeg -i "$URL" -vn -acodec pcm_s16le -ar 48000 -ac 1 -t 60 out.wav`.
Emit a faithful WAV (model input) + an MP3 for playback (MP3 for shared assets,
per Pete's convention) + an optional +N dB amplified MP3 for human listening
only. See `birdnet/tests/fetch-listen-clip.sh` in the repo (the prior Mobotix
`capture-audio.sh` is RTSP/`mobotix.sdp` only — does NOT fit Reolink).

## 4. Geo-filtering must come from the node's GPS, pulled dynamically

`--lat/--lon` (default -1) enable eBird species-range filtering; without them
BirdNET matches the GLOBAL list and you get implausible noise (Garden Warbler,
Common Nightingale, Eurasian Magpie on a Chicago-area cam).

### 4a. THE sentinel-collision bug — `lon > -1` silently disables geo-filtering in the WHOLE Western Hemisphere

This is the highest-value lesson here. The symptom Pete caught: out-of-range
species in the data even though the job passed correct `--lat/--lon` and the pod
logged the coords in its args. Found on H00F 2026-06-23 (birdnet ≤0.1.3), fixed
in 0.1.4 (commit 937eb22).

ROOT CAUSE: the gate that decides whether to build the geo species filter was
```python
if lat > -1 and lon > -1:   # WRONG
```
The intent was "-1 means unset." But H00F's longitude is **-87.98**, and
`-87.98 > -1` is **False**. So for EVERY negative longitude (all of the
Americas — the entire Western Hemisphere) the geo filter was never built;
`species_filter` stayed `None` and BirdNET ran against its full global
6,522-species list. Hence tinamous, pardalotes, Great Tits, Pacific Chorus Frog
showing up in Lemont, IL. The `-1` "unset" sentinel collided with real,
legitimately-negative longitude values.

FIX — test the sentinel explicitly, then validate against geographic ranges:
```python
coords_set   = not (lat == -1 and lon == -1)
coords_valid = -90 <= lat <= 90 and -180 <= lon <= 180
if coords_set and coords_valid:
    ... build geo filter ...
```
Same broken `lat > -1 and lon > -1` pattern was ALSO in the startup `location=`
log gate — fix every occurrence. The auto-resolve gate `if lat == -1 and lon
== -1:` (meaning "both unset → try to resolve") is CORRECT and must be left
alone; only the "is set" tests were wrong.

GENERAL RULE (applies to any plugin doing coordinate/threshold gating): NEVER
use `value > sentinel` to mean "value is set" when the sentinel is a number the
real data can be less than. `-1` as "unset" is fine ONLY with an equality test
(`value == -1` / `not (lat == -1 and lon == -1)`), never an ordering test —
negative longitudes, sub-zero temperatures, etc. will silently fail the gate.

VERIFY THE FILTER ACTUALLY ENGAGES, don't just confirm the args are present.
The earlier verification mistake: confirming the pod's `.spec.containers[0].args`
contained `--lat/--lon` (they did) and assuming filtering worked. It did NOT.
The real proof is a log line at startup:
- WORKING:  `Loading geo model for species filtering (41.7180, -87.9827, ...)`
            then `Geo filter: 124 species expected at this location/time`.
- BROKEN:   neither line appears — the run jumps straight from "starting" to
            "Loading BirdNET V2.4 acoustic model" to "Classified".
Reproduce deterministically with the saved clip + the exact job args, grepping
for `geo|species expected|location=`, rather than fighting brief-pod log timing.

Cross-check against published data: pull `env.detection.audio.summary` for the
node over a few hours and list distinct species. Any species not plausibly in
the node's region (e.g. Australian/European/South-American taxa for a US node)
== the geo filter is OFF. A correct filter yields ~100–130 region-appropriate
species, not the global list. (Introspection confirmed
`geo.predict(41.718,-87.983,week=23).to_set()` returns 128 correct IL species
in the right `Scientific_Common` format that `custom_species_list` accepts, so
once the gate fires the filtering itself is sound.)

Sources for the node's GPS, in order of robustness:
- **Node manifest** `/etc/waggle/node-manifest-v2.json` on the HOST has live
  `gps_lat`/`gps_lon` (H00F: 41.7180, -87.9827). The plugin's
  `read_node_location()` reads this path — but a plain container does NOT see
  `/etc/waggle/` (logs "No node manifest found — geo-filtering disabled"). It
  must be MOUNTED into the pod. A bare `docker run` won't have it; a real SES
  pod may (verify with `kubectl exec` on a running pod before assuming).
- **pywaggle live GPS**: NOT available in this image — `waggle.data.gps` does
  not exist, `Plugin` has no gps method.
- **`sys.gps.*` data-API stream**: NOT published for fixed nodes like H00F.

IMPLEMENTED design (birdnet `read_node_location()`, proven the right shape):
a hybrid resolver that tries sources in order and returns the first hit.
CORRECTED in 0.1.3 — see `node-gps-location-resolution.md` for the canonical,
up-to-date version. Key correction: pywaggle has NO `waggle.data.gps` module
(the import `from waggle.data.gps import GPS` ALWAYS fails — do not use it). The
only live-GPS mechanism is subscribing to the `sys.gps.*` data stream, and that
must be OPT-IN (a `--gps-subscribe` flag, default off) because fixed nodes have
no GPS publisher. Resolution order that actually works:
1. **Node manifest**, probing MULTIPLE paths: `$WAGGLE_NODE_MANIFEST` →
   `/etc/waggle/node-manifest-v2.json` → `/run/waggle/...` → `/host/etc/...`.
2. **Waggle env vars** — `WAGGLE_NODE_GPS_LAT`/`_LON`.
3. **(opt-in) live `sys.gps.*` subscribe** — only for GPS/mobile nodes.

Explicit `--lat/--lon` on the CLI override the whole resolver (handled by the
caller, NOT inside `read_node_location`). This keeps the job YAML portable (no
hardcoded coords) wherever a source is reachable. Explicit `--lat/--lon` in the
job YAML is the zero-risk fallback that enables geo-filtering TODAY but is
node-specific.

ANSWERED EXPERIMENTALLY (H00F, 2026-06-22): **SES does NOT mount the node
manifest into plugin pods.** The deployed birdnet 0.1.2 pod logged "No node
location available (live GPS / manifest / env all absent)" — i.e. the hybrid
resolver tried all sources and found none inside the pod. Combined with: no
pywaggle GPS API in the image, and no `sys.gps.*` stream on this fixed node,
the conclusion is that **on a fixed Sage node you MUST pass explicit
`--lat/--lon` in the job YAML** to get geo-filtering. The dynamic resolver still
earns its place (portable, and will auto-resolve on nodes/setups where a source
IS present — e.g. mobile nodes with live GPS, or a future SES that mounts the
manifest), but do not expect auto-resolution to work on a stock fixed node.
Pull the node's real coords from the HOST manifest once
(`/etc/waggle/node-manifest-v2.json`) and bake them into the job args.
Verification recipe: read a deployed pod's startup log for "Node location from
manifest <path>" (mounted/worked) vs "No node location available …" (must use
explicit coords).

Also confirmed this session: birdnet's `--min-confidence 0.35` change took
effect live (pod logged `min_confidence=0.35`), and the threshold fix was
validated against the captured clip BEFORE deploy (House Sparrow 0.3977/0.3822
now pass; were filtered at 0.60). Always validate a threshold change by running
the saved clip through the new image at the new threshold before cutover.

Convention reminder: this was a code+version+docs-in-ONE-commit change (Pete's
hard rule) — bump `sage.yaml` version, job image tag, AND the README
location-filtering table together; never split them across commits.
