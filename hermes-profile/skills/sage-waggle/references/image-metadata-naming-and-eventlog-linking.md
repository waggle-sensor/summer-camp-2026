# Image metadata, object-store naming, and event-log linking (Sage/pywaggle)

Durable techniques for working with camera images uploaded by Sage plugins:
how they're named, what metadata survives, how to link a downloaded file back
to its event-log record, and the uniqueness pitfalls. Verified against live
data.sagecontinuum.org and pywaggle `main` source, 2026-07.

## 1. pywaggle object naming (who names what)

`plugin.upload_file(path, meta={}, timestamp=None)` — the object-store name is
ALWAYS `f"{timestamp}-{Path(path).name}"`, assembled by pywaggle, NOT the plugin.
- The plugin only supplies the base filename (e.g. `sample.jpg`).
- `timestamp = timestamp or get_timestamp()`; `get_timestamp()` is literally
  `time.time_ns()` (node clock, nanoseconds). Evaluated at UPLOAD time unless the
  caller passes `timestamp=` explicitly.
- Passing `timestamp=capture_ts` makes the name prefix AND the record timestamp
  reflect capture instead of upload. One-line change.
- pywaggle auto-injects ONE meta key: `meta["filename"]`. Constraints:
  `valid_meta()` requires flat `str->str`; `__publish` rejects ts <
  `MIN_TIMESTAMP_NS` (2000-01-01) — the seconds-vs-nanoseconds tripwire.

Two DIFFERENT naming schemes — don't confuse:
- object-store name = `{ts}-{filename}` (what you see in the store)
- on-node staging DIR (`uploader.py`) = `{ts}-{sha1sum}` with `data`+`meta` files
  (the sha is NOT surfaced into the object name or record meta).

## 1b. One-shot upload contract + on-node verification WITHOUT Beehive (VERIFIED)

The full one-shot upload shape for a capture→embed→upload plugin, verified
end-to-end on a live node against real pywaggle:
- `plugin.upload_file(staged_path, meta=<all-strings>, timestamp=capture_ts_ns)`.
  Passing `timestamp=capture_ts_ns` makes BOTH the object key and the record
  timestamp use capture time (§1). ALL meta values MUST be `str` (pywaggle
  `valid_meta` silently needs it) — stringify ints like the ns timestamps.
- Two-timestamp pattern: record `timestamp` = capture ns; `meta["capture_timestamp"]`
  = same (redundant, explicit); `meta["upload_timestamp"]` = `str(time.time_ns())`
  at send. latency = upload − capture (measured ~1.8 s on a real run).
- Telemetry: publish per-phase `plugin.duration.grab` / `.embed` / `.upload` in
  NANOSECONDS (fleet convention) via `plugin.publish(name, ns, timestamp=...)`.
  Best-effort — never fail the upload if a publish throws.
- Import pywaggle LAZILY (inside the function), so unit tests inject a fake plugin
  with no dependency installed. Fail-SOFT at runtime: catch capture/upload
  exceptions, return `(False, {"error": ...})`, map to a nonzero exit — don't
  throw past main(). (Config errors stay fail-FAST, exit 2.)

VERIFY THE UPLOAD CONTRACT ON A NODE WITHOUT NEEDING BEEHIVE: set
`WAGGLE_PLUGIN_UPLOAD_PATH=/tmp/some-dir` before running. pywaggle's `Uploader`
then stages to `/tmp/some-dir/{timestamp}-{sha1}/data`+`meta` instead of the real
upload agent. Assert: (a) the dir name's ts prefix == your capture ts; (b) the
`meta` JSON `timestamp` field == capture ts and `capture_timestamp` label matches;
(c) every value in `meta["labels"]` is a string; (d) the `data` bytes still carry
your EXIF (read_back matches). This proves the entire contract offline; a real SES
job submission is only needed to confirm the cloud RECORD appears in the portal.

## 2. What the server adds vs what the plugin sends

On the wire (rabbitmq.py) the plugin sends only:
`name / value / timestamp / meta{camera, filename}` + the AMQP `app_id` property.
Everything else in the upload record's meta — `vsn, node, host, job, task,
plugin (registry...:VERSION), zone`, lat/lon — is injected SERVER-SIDE by the
validator/data-service, keyed off `app_id` + the k3s scheduler. So node/job
identity is NOT in the plugin payload; it's cloud-enriched after ingest.

## 2b. Where a PLUGIN reads its own node identity (VSN, node id, GPS) — VERIFIED

RULE (do this proactively, before writing any plugin that self-identifies): NEVER
assume a `WAGGLE_*` env var exists for node identity, and NEVER hard-code a test
node's VSN/GPS into plugin code (it ships to the whole fleet — ~100 nodes). Before
relying on ANY platform env var or identity source, VERIFY it two ways: (1) read
pywaggle source for the exact env names it consults; (2) sudo-inspect a live pod +
`/etc/waggle/` on a real node. This session, the user had to prompt "did you
hard-code the node name?" — the check should be automatic. Grep new plugin code
for the test node's VSN (e.g. `H00F`) and geo before committing; the only OK
occurrences are docs/tests/spikes, never `app.py`/`*.py` runtime defaults.

§2 covers what the CLOUD adds. But when the plugin ITSELF needs node identity
(e.g. to build a `<ts>-v2-<vsn>-<camera>.jpg` filename, or embed lat/lon in EXIF),
it must read it locally. THE TRAP (fell into it, cost a rework): there are NO
`WAGGLE_NODE_VSN` / `WAGGLE_NODE_ID` / `WAGGLE_NODE_LAT` / `WAGGLE_NODE_LON`
environment variables. pywaggle reads ONLY messaging-plumbing env vars
(`WAGGLE_PLUGIN_HOST/PORT/USERNAME/PASSWORD`, `WAGGLE_APP_ID`,
`WAGGLE_PLUGIN_UPLOAD_PATH`, `PYWAGGLE_LOG_DIR`) — never node VSN/geo. Inventing
`WAGGLE_NODE_*` fallbacks compiles fine and silently resolves to EMPTY on every
node, so it fails FLEET-WIDE, not just locally. Always verify env-var names
against pywaggle source before relying on them.

Authoritative node-identity source = files under `/etc/waggle/` (verified on a
live Thor node, world-readable `-rw-r--r--`, so a plugin container can read them):
- `/etc/waggle/node-manifest-v2.json` — the rich source. Keys: `.vsn` (e.g.
  "H00F"), `.name` (hardware/node id, e.g. "00004CBB4701D16C"), `.gps_lat`,
  `.gps_lon` (full precision, e.g. 41.7179852752395 / -87.98271513806043),
  `.project`, `.computes[]`, `.sensors[]` (incl. camera `uri`/model!).
- `/etc/waggle/vsn` — just the VSN string. `/etc/waggle/node-id` — just the id.
- Pod env has only `KUBENODE=<hwid>.<compute>` (e.g.
  `00004cbb4701d16c.agx-thor`) — the HARDWARE id, NOT the VSN.

Fleet-portable resolution pattern (precedence high→low, per field): explicit
CLI flag → manifest JSON → `/etc/waggle/{vsn,node-id}` files → None. Auto-reading
the manifest means the same plugin self-identifies on all ~100 nodes with ZERO
per-node config. Make the manifest path overridable (`--node-manifest` / an env
var) for off-node testing, and make the read NEVER raise (missing manifest is
normal in dev/CI → fall back to flags). Note the manifest GPS is far more precise
than any hand-typed lat/lon — prefer it. Reference implementation: image-sampler2
`nodemeta.py` (`load_manifest`, `resolve_identity`).

## 2c. Camera credentials in a job spec — env-only, never argv (design vs. legacy)

Two patterns exist in the beckman plugins; know the difference and prefer the safe
one. LEGACY (yolo-object-counter, sage-bioclip jobs): camera creds passed as a
PLAINTEXT query-param snapshot URL in the job-spec `args`, e.g.
`--snapshot-url "http://IP:PORT/cgi-bin/api.cgi?cmd=Snap&...&user=USER&password=PASS"`.
This LEAKS the password into: pod argv (`kubectl describe pod`), the process list,
scheduler/pod logs, the ECR/SES job record, AND the git-committed job YAML. It
works, but it is a standing secret-exposure.

SAFE (image-sampler2 design): the plugin reads `CAMERA_USER` / `CAMERA_PASSWORD`
from the ENVIRONMENT only, never accepts them as flags/argv. To run such a plugin
as a real SES job you must inject the creds into the pod via env — a k8s Secret +
`env`/`envFrom` in the pod spec — NOT via args. Confirm the SES/sesctl job schema
actually supports secret env refs before assuming it (it may only expose `args`).

Rule for this class of work: never commit a camera/device password, never echo it
to logs, and when you SEE one sitting in a repo (e.g. a job YAML), flag it as a
cleanup item rather than propagating the pattern into a new plugin. When the user
asks "how do the existing plugins handle secrets?", CHECK the actual job YAMLs +
app.py before answering — the answer here was "insecurely, in argv," which is worth
surfacing explicitly rather than copying.

## 3. Object-store URL structure

`https://storage.sagecontinuum.org/api/v1/data/<JOB>/<PLUGIN-VERSION>/<NODE_ID>/<TS>-<FILENAME>`
The path encodes job, plugin+version, node id, timestamp, filename. A bare file
on disk (no path) keeps ONLY the timestamp prefix — all other context is lost.

## 4. Reverse-lookup: filename -> event-log record (verified recipe)

The filename ts prefix IS the record timestamp.
1. Split filename on first `-`: `<ts_ns>` + `<filename>`.
2. Convert ns->UTC (`ts/1e9`).
3. POST `https://data.sagecontinuum.org/api/v1/query`
   `{"start":"<t-2s>","end":"<t+2s>","filter":{"name":"upload"}}` (+`"vsn"` if known).
4. Match the record whose `value` ENDSWITH the object name.
Downloads from the store need auth (401 otherwise): `Authorization: Sage <token>`
(portal token; NRP/nrdstor signed URLs carry `?authz=<scitoken>` and need no header).

## 5. ns-timestamp is NOT a unique key (measured, in production)

Over 24h fleet-wide uploads (~20k records, 58 nodes):
- `(vsn, ns)` — NOT unique (760 same-node + 695 cross-node ns collisions).
  Causes: (a) plugins passing ONE ts to multiple artifacts per cycle; (b) COARSE
  clocks — some producers stamp whole-second ns (trailing zeros); (c) source-file
  mtime stamping.
- `(vsn, ns, filename)` — unique in practice, but NOT by construction.
- Guaranteed-unique key requires a per-artifact token: content SHA, UUID, or seq.
Coarse-clock example diagnosed: node W096 whole-second stamps came ONLY from
`file-forager` (source-file mtime), not the node clock — its other plugins emit
full-resolution ns. So "coarse timestamp" is usually a PLUGIN choice, not a bad
node clock — check per-plugin before blaming NTP/RTC.

## 5b. Data-service honors client-supplied (back-dated) timestamps (verified)

Safe to stamp a record with an OLD timestamp (e.g. capture time when uploading
minutes later). Verified against live data.sagecontinuum.org:
- Across ~18.9k fleet upload records/24h, the API record `timestamp` EQUALS the
  ns prefix in the object name for 100% (gap <1ms) — the service stores + indexes
  by the CLIENT-SUPPLIED timestamp, not its own ingest wall-clock.
- Genuine back-dating works end to end: `file-forager` uploads ~5.5h after the
  source-data time; the oldest such record (~24h back) was retrievable by a ±2s
  window query centered on its OLD record time. No ingest-time clamp/rejection
  observed up to ~24h back (extreme past/future bounds untested).
Consumer pitfall: a back-dated record is INVISIBLE to a "last N minutes" poll
keyed on record time once capture→upload lag exceeds the window. Audit any poller
before switching a producer to capture-time stamping — prefer a fixed relative
lookback + dedup-by-id (safe) over a `max(record-ts seen)` cursor (would
permanently drop back-dated records). The Sage object store also lags ~2 min
cross-country, so size lookback windows generously (≥300s).

## 6. Inspecting camera metadata: JPEG marker scan (no exiftool needed)

Pure-Python: walk `0xFF` markers from offset 2; for each APPn (`0xE0..0xEF`) /
COM (`0xFE`) read `struct.unpack(">H", raw[i+2:i+4])` length and dump payload;
stop at SOS (`0xDA`). `Make`/`EXIF` live in APP1 (`Exif\0\0` prefix); JFIF in
APP0; XMP in APP1 (`http://ns.adobe...`); vendor blocks often in COM.

Findings (raw-preserved native snapshots, marker-scanned):
- **Reolink RLC-811A**: bare JPEG, NO metadata (DQT/SOF/DHT/scan only).
- **Hanwha/Wisenet** (one model, 2560x1920): JFIF header only, NO EXIF.
- **Mobotix M16**: RICH — a `#:M1IMG` COM block (PRD=MOBOTIX, DAT/TIM/TZN true
  camera capture time to ms, per-sensor WIN geometry, ZOM, exposure/noise
  telemetry) + a binary `MXF` block. Far richer than EXIF.
So metadata presence is model-specific and unpredictable (2 of 3 tested embed
nothing). Design vendor-AGNOSTIC, never per-camera special-case.

## 7. The re-encode trap (key acquisition insight)

`cv2.imwrite()` writes ONLY pixels — no EXIF/XMP/COM. pywaggle `Camera()` ->
OpenCV `VideoCapture` -> libav DECODES to a numpy array, so ALL camera metadata
is gone before the plugin sees the frame, for every vendor. A re-encoded JPEG is
identifiable by a `Lavc<ver>` (libavcodec) COM tag — that's the fingerprint of
"decoded and re-encoded, metadata destroyed." Same Mobotix camera: the
re-encoding `mobotix-scan` plugin produced a bare Lavc JPEG; the raw-preserving
`imagesampler` variant kept the full M1IMG block.

To preserve camera metadata: fetch the camera's NATIVE still endpoint, save the
RAW JPEG BYTES untouched, and INJECT added EXIF/COM without a pixel decode/
re-encode. OpenCV/RTSP is the lossy fallback for stream-only cameras. Native
still endpoints: Reolink `cgi-bin/api.cgi?cmd=Snap`; Hanwha
`/stw-cgi/video.cgi?msubmenu=snapshot&action=view`; Mobotix
`/cgi-bin/image.jpg`, `/record/current.jpg`, `/control/event.jpg?sequence=head`.

## 8. RTSP sample.timestamp semantics

`ImageSample.timestamp` on the RTSP path = host `time_ns()` at frame GRAB (node
clock), set by a background daemon that grabs every ~10ms — so it can be up to
~10ms stale, and it is NOT camera exposure time and NOT the RTP timestamp. There
is also an unmeasured camera->node encode+network+decode delay. For a trustworthy
key, prefer the node clock (RTC/GPS-disciplined) over any camera-reported time;
camera clocks may be freshly flashed/power-cycled and wrong.

## 9. EXIF embedding recommendation (when authoring provenance into a JPEG)

EXIF has no arbitrary key/value. Best practice = HYBRID: standard tags where one
fits (Model=vsn, Software=plugin:ver, DateTimeOriginal=capture (+SubSecTime/
OffsetTime), ImageUniqueID=<sha256>, GPS=lat/lon) PLUS a complete JSON blob in
UserComment for lossless round-trip of all fields.

CRITICAL — the unique_id CANNOT be "SHA256 of the FINAL saved bytes" if you also
embed it (self-reference paradox: adding the hash to the EXIF changes the bytes,
so hash(final_file) can never equal a value stored INSIDE final_file). Verified
the hard way. Correct semantics:
  - unique_id = SHA256 of the ORIGINAL captured frame (BEFORE any EXIF injection).
    Stable, reproducible from the source frame, uniquely identifies the capture.
    Write it to BOTH the UserComment JSON and ImageUniqueID (they then agree).
  - If you also want an integrity hash of the FINAL stored object, put THAT in the
    upload meta (outside the file, at upload time) where it can equal the object
    without paradox — do NOT embed it.
Do NOT try to "hash after insert then re-insert" — it just makes ImageUniqueID
disagree with the file's own hash. One clean pass: hash the raw frame, put that in
both JSON and the tag, inject once.

## 10. Injecting EXIF WITHOUT re-encoding — use piexif (VERIFIED 2026-07)

`piexif` (pure-Python, MIT) is the right tool to add the §9 hybrid EXIF to a
native-raw JPEG WITHOUT decoding pixels and WITHOUT stripping foreign camera
segments (the §7 requirement). Do NOT use `Image.save(..., exif=...)` (Pillow) —
that re-encodes the pixels. Build with `piexif.dump(exif_dict)`, insert with
`piexif.insert()`.

Empirically verified on a JPEG carrying a foreign COM segment (Mobotix-style
M1IMG): `piexif.insert` splits the JPEG into segments and re-emits them, placing
our APP1/Exif at position 1 and PUSHING existing foreign segments down — it does
NOT drop them. The COM survived; the compressed pixel scan (SOS..EOI) was
BYTE-IDENTICAL before/after (proof of no re-encode). To confirm no re-encode in
your own test: compare `data[data.index(b"\xff\xda"):]` (SOS→EOI) before/after.

FOUR piexif gotchas that WILL bite (all confirmed against piexif 1.1.3):
1. In-memory bytes need a SINK. `piexif.insert(exif_bytes, image, new_file)`:
   when `image` is bytes (not a filename) you MUST pass a 3rd arg — an
   `io.BytesIO()` or output path — else it raises
   `ValueError: Give a 3rd argument`. It only writes in place when `image` is a
   path. Pattern: `sink=io.BytesIO(); piexif.insert(exif_bytes, raw, sink);
   out=sink.getvalue()`.
2. UserComment needs an 8-byte charset prefix: store
   `b"ASCII\x00\x00\x00" + json_str.encode("ascii")`; strip the first 8 bytes
   when reading back.
3. GPS CANNOT be signed. `piexif.dump` raises `struct.error` on negative lat/lon.
   Store the ABS value as DMS rationals + a ref: `GPSLatitudeRef` "N"/"S",
   `GPSLongitudeRef` "E"/"W". (e.g. lon -87.9827 → (87,1)(58,1)(...) ref="W".)
4. unique_id = SHA256 of the ORIGINAL frame (before insert), NOT the final bytes.
   A hash of the final file cannot live inside that file (self-reference paradox
   — see §9). Hash the raw camera bytes once, write that to BOTH the UserComment
   JSON and ImageUniqueID in a single injection pass. (Earlier drafts of this doc
   said "hash the final injected bytes" — that is WRONG and was corrected after it
   bit a real build.)

VERIFIED END-TO-END ON A LIVE NODE (H00F Reolink 4K, 2026-07): fetch native-raw
`cmd=Snap` (~1.3 MB bare JPEG, no APP0/APP1/COM) -> build hybrid EXIF -> single
`piexif.insert` -> save. Result: APP1/EXIF added (+~984 bytes), compressed pixel
scan (SOS..EOI) BYTE-IDENTICAL to the raw capture, unique_id == SHA256(raw),
UserComment JSON unique_id == ImageUniqueID tag, all provenance fields round-trip
via a `piexif.load` + strip-8-byte-prefix + `json.loads` reader. This is the
reference implementation shape for any Sage image plugin embedding provenance.

The `image-sampler2` repo carries a runnable 6-check spike proving all of this:
`spikes/exif_spike.py` (foreign-segment survival, byte-identical pixels, JSON +
SHA256 round-trip, negative-lon GPS). Reproduce-with-modifications when validating
EXIF injection for a new plugin/camera. Add `piexif` to the plugin requirements.
