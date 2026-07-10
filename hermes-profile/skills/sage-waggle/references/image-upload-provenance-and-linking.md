# Image Upload Provenance, Timestamps & Event-Log Linking

How Sage/pywaggle names uploaded files, what metadata travels with them, how to
link a downloaded file back to its event-log record, and the uniqueness pitfalls.
All verified against pywaggle `main` source + live `data.sagecontinuum.org` in
2026-07.

## Object-store name = `{timestamp}-{filename}` (pywaggle builds it)

A stored object like `1783082577307441180-sample.jpg` is named by **pywaggle**,
not the plugin. The plugin only supplies the base filename (e.g. `sample.jpg`).

- `Plugin.upload_file(path, meta={}, timestamp=None, keep=False)` (src/waggle/plugin/plugin.py):
  `timestamp = timestamp or get_timestamp()` → object name = `f"{timestamp}-{Path(path).name}"`.
- The number is a **nanosecond epoch** integer (`get_timestamp()` == `time.time_ns()`,
  src/waggle/plugin/timestamp.py). Same value is used for the object name prefix,
  the `upload` message `timestamp`, and the sidecar meta.
- **Two naming schemes — don't confuse them:**
  - Object-store / staged object = `{timestamp}-{filename}` (what you see in the store).
  - On-node staging DIR (`Uploader.upload_file`, uploader.py) = `{timestamp}-{sha1sum}/`
    containing `data` + `meta` files. Checksum-based, NOT the object name.
    NB: pywaggle already computes a sha1 here but never surfaces it into the
    object name or the upload record.

## What pywaggle attaches vs what the SERVER attaches

pywaggle emits ONE `name="upload"` message with:
- `name="upload"` (RESERVED — a plugin cannot `publish()` this name; `raise_for_invalid_publish_name` blocks it)
- `value` = the staged object name `{timestamp}-{filename}`
- `timestamp` = the single ns time field (capture time if you pass `timestamp=`, else upload time)
- `meta` = your dict PLUS one auto-injected key: `meta["filename"] = Path(path).name`.
  pywaggle adds ONLY `filename`.

Everything else you see in the data API — `vsn`, `node`, `host`, `job`, `task`,
`plugin` (the `registry…:version` tag), `zone`, lat/lon — is injected
**server-side** (validator/data-service), keyed off the AMQP `app_id` property
(`WAGGLE_APP_ID`) + the k3s scheduler. It is NOT in the plugin's message. (See
rabbitmq.py: the only wire-level context added is the `app_id` property.)

### Hard constraints pywaggle enforces (bit us / worth knowing)
- `valid_meta()`: meta MUST be a flat dict of **str → str**. Stringify everything,
  e.g. `meta["capture_timestamp"] = str(sample.timestamp)` (not an int).
- `MIN_TIMESTAMP_NS` guard: `__publish` rejects any timestamp < 2000-01-01 (ns).
  This is the seconds-vs-nanoseconds tripwire — any hand-built timestamp must be ns.

## `sample.timestamp` semantics (RTSP / Camera) — grab time, NOT exposure time

From src/waggle/data/vision.py:
- `Camera` uses a background daemon for non-`file://` sources (RTSP/HTTP). The
  daemon loops: `grab()` then `self.timestamp = get_timestamp()` (host `time_ns()`),
  `sleep(0.01)`. `snapshot()` returns the last daemon frame with the daemon's stored ts.
- So `sample.timestamp` is **host-clock frame-GRAB time on the node**, up to ~10 ms
  stale, NEVER the RTP/sensor/camera timestamp. OpenCV decode discards all camera
  metadata; the code even notes OpenCV's RTSP FPS is garbage ("returns 180000")
  so pywaggle ignores camera timing entirely.
- Also unmeasured: the camera→node encode+network+decode-buffer delay.
- Other sources: USB/non-daemon = ts right after synchronous grab; `file://` video
  = synthesized `base + frame_idx/fps`; `ImageFolder` = file `st_mtime_ns`.

### Two-timestamp best practice (for batch-and-hold / decoupled capture→upload)
pywaggle carries only ONE time. If you capture at T0, hold, upload at T1, T0 is
lost unless you record it. Recommended:
1. Authoritative record ts = capture: `upload_file(path, meta=meta, timestamp=sample.timestamp)`
   → object name + record ts reflect grab time regardless of hold.
2. Preserve upload time in meta: `meta["upload_timestamp"] = str(get_timestamp())`.
3. Optional redundancy: `meta["capture_timestamp"] = str(sample.timestamp)`.
4. `upload_timestamp - timestamp` = hold+stage+upload latency (measures the
   cross-country object-store lag directly).
Label it honestly as "node grab time," not "exposure time."

## Linking a downloaded file back to the event log

The filename ts prefix IS the record `timestamp`, so:
1. Split filename on first `-`: `<ns>` + `<base>`.
2. `<ns>/1e9` → UTC instant.
3. POST `https://data.sagecontinuum.org/api/v1/query` with
   `{"start":<t-2s>,"end":<t+2s>,"filter":{"name":"upload"}}` (add `"vsn"` if known).
4. Match the record whose `value` endswith your object name. (±2 s window absorbs slack.)

Verified: a ±2 s window returned exactly one matching upload record with full meta.

## ns-as-key is NOT unique (verified in production)

Over 24 h of fleet-wide `upload` records (~20 k records, 58 nodes):
- **760 same-node** ns collisions + **695 cross-node** ns collisions.
- Causes: (a) one plugin cycle passing the SAME `timestamp=` to multiple
  `upload_file()` calls (e.g. mobotix-scan uploaded 6 artifacts at one ns);
  (b) coarse clocks — file-forager stamps by source-file second-resolution mtime,
  producing whole-second ns (`ns % 1e9 == 0`); (c) source-file-time stamping.
- Tested keys: `(vsn, ns)` → collisions; `(vsn, ns, filename)` → 0 collisions
  (unique in practice); `(vsn, full-object-name)` → 0.
Conclusion:
- VSN disambiguates cross-node; the FILENAME disambiguates same-node/same-ns batches.
- imagesampler's constant `sample.jpg` is itself collision-prone → use a
  **per-stream filename** (`<camera>.jpg`).
- Even `(vsn, ns, filename)` is unique in practice but NOT by construction (coarse
  clock + same stream + same second still collides). For a guaranteed 1:1 key add
  a per-capture unique id: monotonic sequence, uuid4, or content-sha (pywaggle
  already computes a sha1 on staging — candidate to surface).

### Coarse-clock finding (upstream, not a node clock fault)
A node showing whole-second upload ts (many trailing zeros) is usually NOT a bad
node clock. Diagnose by checking whether OTHER plugins on the same node emit
full-resolution ns (they will) — the coarse stamps come from one plugin choosing
source-file mtime. Raise with that plugin's author / Sage data conventions, not ops.

## What a downloaded JPG alone tells you

- `cv2.imwrite` (pywaggle `ImageSample.save`) writes **raw pixels only** — no EXIF,
  no XMP, no JFIF, no comment. A downloaded jpg is provenance-orphaned; only the
  filename ts + (if you kept it) the URL path (`…/data/<JOB>/<PLUGIN-VER>/<NODE_ID>/<ns>-<file>`)
  carry context.
- To make files self-describing, author EXIF at save time (see camera-metadata ref).
