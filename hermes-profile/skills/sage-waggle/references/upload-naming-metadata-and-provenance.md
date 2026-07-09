# pywaggle Upload Naming, Metadata & Image Provenance

How uploaded files are named, what metadata travels with them, how to link a
downloaded file back to the event log, and the pitfalls. All verified against
pywaggle `main` source + live Sage data API (2026-07).

Source of truth in pywaggle:
- `src/waggle/plugin/plugin.py` — `Plugin.upload_file`, `__publish`, `valid_meta`
- `src/waggle/plugin/uploader.py` — on-node staging layout
- `src/waggle/plugin/rabbitmq.py` — what goes on the wire
- `src/waggle/data/vision.py` + `data/timestamp.py` — Camera/snapshot timestamps

## 1. Object-store name = `{timestamp}-{filename}`

`plugin.upload_file("sample.jpg", meta={...})` produces an object named e.g.
`1783082577307441180-sample.jpg`. The plugin only supplies the base filename;
**pywaggle prepends the timestamp**. The number is a NANOSECOND epoch integer
(`time.time_ns()`), UTC. It is the SAME value used as the record `timestamp` and
in the sidecar meta — so the filename prefix IS the record timestamp.

Full object-store URL is structured/self-describing:
`https://storage.sagecontinuum.org/api/v1/data/<JOB>/<PLUGIN-VERSION>/<NODE_ID>/<TIMESTAMP>-<FILENAME>`

Two DIFFERENT naming schemes exist — don't confuse them:
- object/store name = `{timestamp}-{filename}` (what you see in the store)
- on-node staging DIR (`uploader.py`) = `{timestamp}-{sha1sum}/` containing
  `data` + `meta` files. The sha1 is computed but NOT surfaced into the object
  name or the upload record meta.

## 2. What pywaggle attaches vs. what the server attaches

`upload_file` emits ONE message: `name="upload"` (reserved — plugins can't
publish this name themselves), `value=<object name>`, `timestamp`, and `meta`.
pywaggle auto-injects only ONE meta key: `filename`. So a bare imagesampler
upload's plugin-side meta is just `{"camera": <name>, "filename": "sample.jpg"}`.

Everything else you see in the data API — `vsn`, `node`, `host`, `job`, `task`,
`plugin` (the `registry...:version` tag), `zone` — is injected SERVER-SIDE by the
validator/data-service, keyed off the AMQP `app_id` property (`WAGGLE_APP_ID`)
set in `rabbitmq.py`, AFTER the message leaves the node. The plugin sends only
`name/value/timestamp/meta{camera,filename}` + the `app_id` property.

Hard constraints enforced on every publish/upload:
- `valid_meta()`: meta MUST be a flat dict of **str → str**. Stringify anything
  else (`meta["capture_timestamp"] = str(ns)`), never pass an int.
- `MIN_TIMESTAMP_NS` guard: `__publish` rejects any timestamp < 2000-01-01 (ns).
  This is the seconds-vs-nanoseconds unit tripwire; hand-built timestamps must be
  nanoseconds since epoch.

## 3. Timestamp semantics — capture vs. upload

`upload_file(path, meta=, timestamp=, keep=)` accepts `timestamp=`. If omitted,
pywaggle calls `get_timestamp()` at UPLOAD time. So by default the record/name
timestamp is when the file was staged for upload, NOT when it was captured. To
stamp with capture time: `plugin.upload_file(path, meta=m, timestamp=sample.timestamp)`.

**Two-timestamp pattern** (use when capture and upload are decoupled — batch
pull, hold-for-analysis, or cross-country object-store lag, where the gap grows
from ms to minutes):
- record `timestamp` = capture time (`sample.timestamp`) — authoritative join key
- `meta["upload_timestamp"] = str(get_timestamp())` captured at the upload call
- optional `meta["capture_timestamp"] = str(sample.timestamp)` for redundancy
- `upload_timestamp - timestamp` = hold+stage+upload latency (a free drift metric)

### RTSP `sample.timestamp` is NODE GRAB time, not camera exposure time
`waggle.data.vision`: for non-`file://` sources (RTSP/HTTP) a daemon thread runs
`grab()` then `self.timestamp = get_timestamp()` (host `time.time_ns()`) every
~10 ms; `snapshot()` returns the last daemon frame + that stored stamp. So:
- host-clock grab time, never the RTP/sensor/EXIF timestamp
- up to ~10 ms stale vs. the returned frame
- does NOT capture the camera→node encode+network+decode delay (tens–hundreds ms)
Other sources: USB non-daemon = grab time (no 10 ms staleness); `file://` video =
`base + frame_index/fps` (synthesized); `ImageFolder` = file `st_mtime_ns`.
Perf note: `Camera.snapshot()` opens+tears-down the RTSP daemon per call — for
batch pulls hold ONE `Camera` open and use `stream()`/repeated grabs.

## 4. What a downloaded JPG tells you (and what it doesn't)

imagesampler saves via `ImageSample.save()` → `cv2.imwrite()`, which writes RAW
PIXELS ONLY — no EXIF, no XMP, no comment, no timestamp/camera/GPS/exposure.
From the bytes you get only dimensions + a generic JFIF header. From the FILENAME
you get the ns timestamp prefix. From the full URL path you get job/plugin/node.
A bare file with no path retains only the timestamp. => To make images
self-describing, embed EXIF at save time (Pillow/piexif; prefer INJECT without
re-encode so you don't re-compress and, on camera-JPEG paths, don't drop camera
EXIF). Camera EXIF (make/focus/exposure) does NOT survive the RTSP→OpenCV→numpy
path (it's decoded to pixels); it only survives if you fetch the camera's HTTP
CGI JPEG snapshot bytes directly, or query ONVIF and merge.

## 5. Linking a downloaded file back to the event log (verified recipe)

The filename ns prefix IS the record timestamp:
1. Split filename on first `-`: `1783082577307441180` + `sample.jpg`
2. ns → UTC: `1783082577307441180 / 1e9`
3. Query `name="upload"` in a tight window (±2 s absorbs slack):
   `POST https://data.sagecontinuum.org/api/v1/query`
   `{"start":"...","end":"...","filter":{"name":"upload","vsn":"H00F"}}`
4. Match the record whose `value` ENDSWITH your object name.

## 6. PITFALL: nanoseconds are NOT a unique key

Verified against 24h fleet-wide `upload` records (20,375 recs, 58 nodes):
- `(vsn, ns)` → 760 same-node + 695 cross-node collisions. NOT unique.
- `(vsn, ns, filename)` → 0 collisions. Unique in practice, NOT by construction.

Collision causes: (a) one plugin cycle uploads multiple artifacts with the SAME
`timestamp=` (e.g. mobotix-scan: 6 objects at one ns, differing only by
filename); (b) COARSE CLOCKS — some records have whole-second ns
(`ns % 1e9 == 0`). imagesampler's constant `sample.jpg` filename makes IT prone
to `(vsn,ns,filename)` collisions on multi-stream/same-second capture.

For a construction-guaranteed unique key, add a per-capture token: monotonic
sequence, UUID, or the content SHA (pywaggle already computes sha1 on staging but
doesn't expose it). Put `vsn` + timestamps + the token in BOTH the filename/EXIF
and the upload record meta.

### Coarse-clock diagnosis method (whole-second timestamps)
If a node shows whole-second upload stamps, check whether it's the NODE clock or
ONE plugin: count trailing zeros of the ns in `value`'s object name, grouped by
`meta.plugin`. Real case: W096 showed whole-second stamps, but imagesampler +4
other plugins on the SAME node emitted full-resolution ns — only `file-forager`
was coarse (it stamps by the source file's second-resolution mtime, not
`time_ns()`, and reuses one second across the .ghg/.zip pair). => plugin-level
provenance choice, not a node clock fault. A source-file mtime masquerading as
capture time is also an argument for the explicit two-timestamp convention.

## Reusable data-API query snippet (no MCP needed)
```python
import json, urllib.request
def query(name, vsn="H00F", start="-24h", end=None):
    body={"start":start,"filter":{"vsn":vsn,"name":name}}
    if end: body["end"]=end
    req=urllib.request.Request("https://data.sagecontinuum.org/api/v1/query",
        data=json.dumps(body).encode(), headers={"Content-Type":"application/json"})
    return [json.loads(l) for l in urllib.request.urlopen(req,timeout=90)
            .read().decode().splitlines() if l.strip()]
# ns from an object name: value.rsplit("/",1)[-1].split("-",1)[0]
```
