# pywaggle2 — Design Doc (DRAFT / discussion)

Status: DRAFT for discussion. A proposal for a next-generation Waggle plugin
client library ("pywaggle2") that fixes the acquisition/metadata and
node-identity gaps we hit repeatedly while building image-sampler2, birdnet,
yolo, and bioclip. Written to be lifted into an upstream design/RFC for
`waggle-sensor/pywaggle`.

Author: Pete Beckman <pete.beckman@northwestern.edu>
Companion: `~/AI-projects/Infra-problems-to-fix.md` (the raw issue list this
distills), `image-sampler2` (reference implementation of the still-first
acquisition + EXIF-injection pattern).

---

## 0. One-paragraph thesis

Today's pywaggle `Camera` takes the easy, uniform route: every camera, regardless
of what it supports, is opened through OpenCV → FFmpeg/libav, decoded to pixels,
and (on save) re-encoded to JPEG. That is simple and universal, but it is blind to
richer, loss-free paths a camera may offer, and it silently destroys any
camera-authored metadata. Separately, a running plugin has no supported way to
learn its own node identity (VSN) or location (GPS lat/lon). pywaggle2 should (a)
acquire the best image with the most metadata a camera can provide, biasing hard
toward no-reencode, and sliding down to a plain decoded frame only as a last
resort; and (b) expose node identity and location as first-class calls. image-
sampler2 and every other image plugin would then just call pywaggle2 and get the
best image + best metadata the camera streams provide, for free.

---

## 1. Acquisition & metadata: the core redesign

### 1.1 The problem in one comparison (verified on the fleet)

Same Mobotix camera (W08D), two acquisition paths, opposite outcomes:

| Acquisition path | Camera metadata in the stored JPEG |
|---|---|
| libav/FFmpeg decode → re-encode (what pywaggle Camera does) | STRIPPED — only a `Lavc58.54.100` encoder tag remains |
| raw native still (JPEG bytes, NOT re-encoded) | FULL Mobotix `#:M1IMG` fingerprint (~2 KB): manufacturer, frame#, **true camera-side capture time** (ms+µs), per-sensor exposure/geometry, MXF calibration block |

The ONLY difference is re-encode vs raw bytes. The `Lavc...` tag is the tell that a
frame went through FFmpeg/libav (OpenCV's backend) and therefore lost everything.

### 1.2 The crucial correction: metadata does NOT live in the RTSP video stream

A natural but WRONG assumption is "pull raw bytes over RTSP instead of
re-encoding, and metadata is preserved." It is not, for the streams these cameras
actually serve:

- The WSN cameras (Hanwha **XNV-8081Z**, **XNF-8010RV**) are triple-codec
  **H.265 / H.264 / MJPEG**, ONVIF, attached as top/bottom pairs. All are IP
  cameras; all speak RTSP.
- The RTSP **main/sub** stream is **H.264 or H.265** — inter-frame compressed
  video (I/P/B NAL units). There is **no per-frame JPEG/EXIF envelope** in that
  stream. The camera's still-image metadata was never transmitted. So a raw
  keyframe grab yields a metadata-free (and not even JPEG) frame; OpenCV
  re-encoding "loses" nothing metadata-wise there because there was nothing to
  lose — only a generation of pixel quality.
- The metadata-rich, loss-free path is a **separate endpoint**, not the video
  stream:
  - **HTTP/vendor snapshot still** returning a real JPEG with the camera's
    segments intact (Reolink `cmd=Snap`, Hanwha SUNAPI
    `/stw-cgi/video.cgi?msubmenu=snapshot&action=view&Profile=P&Channel=N`,
    Mobotix `/record/current.jpg` / `/cgi-bin/image.jpg`).
  - **MJPEG RTSP profile** (when configured): every RTSP frame IS a full JPEG, so
    a raw frame grab preserves metadata and OpenCV re-encode would destroy it.
  - Hanwha's SUNAPI snapshot returns a JPEG "based on the MJPEG profile" and
    ERRORS if no MJPEG profile is configured — i.e. the still endpoint requires an
    MJPEG profile to exist on the camera.

### 1.3 The acquisition ladder pywaggle2 should try (best → floor)

`Camera.snapshot()` should attempt, in order, and return the first that succeeds,
tagging the result with how it was obtained:

1. **Native HTTP/vendor snapshot still** — raw JPEG bytes, camera metadata
   preserved. `acquisition_path = "native-http-still"`. Best.
2. **MJPEG RTSP profile frame** — raw JPEG frame, no decode. `"mjpeg-rtsp-raw"`.
   Metadata preserved when the camera authors it.
3. **H.264/H.265 RTSP decode → JPEG** (today's OpenCV path) — lowest common
   denominator. `"opencv-reencoded"`. No metadata exists in the stream to lose;
   only pixel re-compression. Universal fallback / floor.

Bias is always toward the highest rung the camera supports; slide down only when
forced. This is the "always prefer no-reencode + camera metadata, fall to a plain
raw image as the floor" principle, made concrete.

**Failure contract.** The rungs are tried in order; a rung that is *inapplicable*
(no snapshot URL, no MJPEG profile) is skipped silently and the ladder falls
through to the next. A rung that is *applicable but fails* (snapshot URL returns
5xx/timeout, RTSP connect refused) is logged (credentials redacted, §3.2) and the
ladder still falls through. `snapshot()` raises `CameraError` ONLY when every
applicable rung has been exhausted — i.e. the camera is genuinely unreachable /
produced nothing. It never returns `None` and never returns a partial/empty
`Snapshot`: a returned `Snapshot` always carries valid bytes. The exception
message names which rungs were attempted and why each failed, so a plugin author
can tell "camera down" from "misconfigured URL" without packet-capturing. (This
mirrors image-sampler2, where a failed acquisition is a hard error the scheduler
sees, not a silent empty upload.)

### 1.4 Where the vendor knowledge belongs

Vendor-aware "try the native still, else fall back to OpenCV" is **camera-domain
knowledge, not plugin-domain knowledge**. Today every image plugin (imagesampler,
yolo, bioclip, birdnet camera-mode) either re-implements it or forgoes it. Putting
the ladder inside pywaggle2's `Camera` gives ALL plugins metadata preservation for
free and lets image-sampler2 shrink back to: call `Camera.snapshot()`, save the
raw bytes, inject Sage fields, upload.

### 1.5 Metadata injection contract (never rebuild)

When a plugin adds Sage provenance fields (vsn, node, job/task, plugin+version,
capture ts, upload ts, per-capture uid, lat/lon), pywaggle2 should INSERT an
EXIF/COM segment into the existing JPEG byte stream (piexif-style), leaving the
camera's own segments intact — NEVER pixel-decode to add metadata. `snapshot()`
returns a `Snapshot` object (the acquisition-side analog of §2's `NodeInfo`)
exposing:
- `.raw_bytes` — the untouched camera JPEG (for the raw-preserving path)
- `.data` — decoded pixels (numpy), lazily. When acquisition was
  `native-http-still` / `mjpeg-rtsp-raw` (the raw-JPEG rungs), the first `.data`
  access decodes `.raw_bytes` on demand and caches the array — so `.raw_bytes`
  stays the untouched original for upload while `.data` serves pixels to ML
  callers. When acquisition was `opencv-reencoded` the pixels already exist and
  `.raw_bytes` is the encoded result. Requires the `[vision]` extra (see §3.1);
  raises `ImportError` if the caller asks for pixels without it.
- `.acquisition_path` — which rung produced it (see 1.3)
- `.camera_capture_time` — parsed camera-side time when present (e.g. Mobotix
  TIM/TZN/TIT); else None → caller uses node grab-time
- `.timestamp` — node grab-time (as today), always present

### 1.6 Camera resolution (keep the good parts)

Preserve today's `Camera(device)` ergonomics:
- Named shortcut (`top_camera`, `bottom_camera`) → resolve via WES
  `data-config.json` to the real URL(s).
- Explicit URL (`rtsp://…`, `http://…`) → used directly.

ADD: the data-config entry (or a companion) should be able to advertise the
camera's **snapshot still URL** and **whether an MJPEG profile exists**, so the
ladder in 1.3 can pick the best rung for a NAMED camera without per-plugin config.
For explicit URLs, pywaggle2 can vendor-sniff (Reolink/Hanwha/Mobotix URL shapes)
or accept an optional `snapshot_url=` hint.

---

## 2. Node identity & location as first-class calls (Infra #1)

### 2.1 Problem

A running plugin cannot learn its own **VSN** (e.g. `H00F`) or **GPS lat/lon**.
Verified four ways: pywaggle 0.56 has no location/identity API (no
`waggle.data.gps`, no `Plugin.get_location()`, no `Plugin.get_vsn()`); the
plugin-writing docs expose only publish/subscribe/upload_file/timeit; a live `ses`
pod has only `WAGGLE_PLUGIN_*` / `WAGGLE_APP_ID` / `WAGGLE_SCOREBOARD` env and
mounts only `/run/waggle/{uploads,data-config.json}`; and the authoritative
`/etc/waggle/node-manifest-v2.json` (+ `/etc/waggle/vsn`, `/etc/waggle/node-id`)
is a node-HOST path NOT mounted into pods (so it appears to work in host-run spikes
and then fails in the pod — actively misleading).

(The one live position source that DOES exist — the `wes-gps-server` gpsd socket —
is unwrapped by pywaggle and yields position only, never identity; see §2.2.1. Its
existence is why the fix belongs in a library accessor, not why the gap is absent.)

Node identity is currently attached DOWNSTREAM by Beehive via message routing
(confirmed: an upload with placeholder filename vsn `NODE` returned from the data
API with `meta.vsn=H00F`, `meta.node=00004cbb4701d16c`). So attribution is correct
without the plugin knowing — but the plugin still cannot build a correct
self-describing filename, embed a real EXIF geotag, or geo-filter ML results, and
non-Python/data-plane consumers of the bare file have no node context.

### 2.2 Proposed pywaggle2 API

A first-class accessor mirroring `waggle.data.audio.Microphone` /
`.vision.Camera`:

```python
info = Plugin.get_node_info()
# -> NodeInfo(vsn, node_id, lat, lon, alt, fix_time,
#            location_source, mobility)
```

- Fixed nodes: return manifest coordinates (`gps_lat`/`gps_lon`) + `vsn`/`node_id`.
- Mobile nodes: return a LIVE GPS fix (with `fix_time`, `alt`) from the
  `wes-gps-server` gpsd service (§2.2.1), falling back to manifest coords if no fix.
- `location_source` distinguishes `"gps-live"` vs `"manifest"` vs `"unavailable"`.
- Convenience shims: `Plugin.get_vsn()`, `Plugin.get_location()`.
- **Never fabricate.** When location is genuinely unknown, return None for
  lat/lon (callers OMIT EXIF GPS rather than writing fake coordinates) — this is
  the rule image-sampler2 already enforces.

#### Mobility: static vs mobile (poll-once vs poll-periodically)

`NodeInfo.mobility` is a **tri-state**: `"static" | "mobile" | "unknown"`.

Rationale: a plugin needs to know whether re-polling location is EVER worthwhile.
On a **static** node the coordinates never change, so a plugin should resolve
identity/location ONCE at startup and never call again — asking repeatedly is pure
waste. On a **mobile** node (a vehicle- or drone-mounted node) location changes
over time, so a plugin MAY choose to re-poll on a cadence its science dictates.
Without this field every plugin either over-polls a live GPS it doesn't need or
hard-codes a mobility assumption that silently breaks when the node type changes.

Why tri-state and not a bare `is_mobile: bool`: `"unknown"` is a real, common
state (an older manifest with no mobility field, or the manifest/WES injection
unavailable). It must drive CONSERVATIVE behavior, not be silently coerced to a
wrong default — collapsing it into a bool forces a static-or-mobile guess and
bakes in a latent bug. (`Plugin.is_mobile()` MAY exist as a convenience shim, but
returns `None` for unknown; the authoritative value is the tri-state.)

**Semantics to document precisely:** `mobility == "mobile"` means "this node's
location is NOT fixed" — it is mounted such that it can change position WITHOUT
significant human intervention (a vehicle- or drone-mounted node), as opposed to a
pole/enclosure mount that requires a deliberate physical reinstall to move. The
flag says NOTHING about instantaneous motion: a mobile node parked for three days
is still `mobile`, and the designation cannot tell you whether it is moving at this
instant. A `static` node is one that cannot move without that significant human
intervention. So the flag governs whether re-polling is ever
warranted; the plugin still owns the cadence. (No `moved_since()` delta helper in
v1 — over-engineering; revisit if a real consumer needs it.)

#### Caching contract: make "resolve once on static nodes" automatic

Rather than make every plugin author remember to cache-if-static, the library
bakes the behavior in via an optional freshness bound:

```python
info = Plugin.get_node_info()            # always a fresh resolve (force-refresh)
info = Plugin.get_node_info(max_age=30)  # cached: re-fetches the LIVE GPS only if
                                         # mobility == "mobile" AND the cached fix
                                         # is older than 30 s; for static/unknown
                                         # nodes returns the cached value forever
                                         # (one resolve for the life of the plugin)
```

Result: on a static node the live-GPS path is hit at most once regardless of how
often the plugin calls, exactly the "ask once and be done" behavior — but the
plugin didn't have to implement it. On a mobile node the plugin passes whatever
`max_age` its use case needs. `get_node_info()` with no `max_age` always does a
fresh resolve for callers that want to force it. `vsn`/`node_id`/`mobility` are
deployment-stable and always served from cache after the first resolve.

**Cache scope & concurrency.** The `max_age` cache is process-local (a
module-level cache on the `Plugin`), not shared across pods or across separate
processes in the same pod. Access is guarded by a lock so a multi-threaded plugin
(worker threads each calling `get_node_info()`) sees a single coherent resolve
rather than a thundering-herd of concurrent GPS reads — the first caller resolves,
the rest block briefly and get the cached fix. `NodeInfo` itself is an immutable
value object, safe to share across threads once returned.

#### 2.2.1 Live-GPS source: `wes-gps-server` (gpsd on :2947)

The live-fix branch above is not hypothetical — WES already runs a GPS service
that pywaggle2 wraps, and we have READ A LIVE FIX FROM IT (2026-07-08, W09E; see
§6.1 for the capture). Documenting it here so the API reads as "we know this exists
and here is exactly how pywaggle2 uses it" (verified from the pod env, the WES
service inventory, pywaggle 0.56 source, and a live on-node read):

**Two independent axes — do not conflate them.** A node has both:
- **Deployment mobility** (a property of the *installation*): bolted to a pole vs.
  mounted on a vehicle/drone. This is what `mobility` (static/mobile/unknown)
  describes. Today every node in the fleet is `static` on this axis.
- **GPS-fix liveness** (a property of the *hardware*): does the node have a GPS
  receiver running gpsd emitting fresh TPV fixes? MANY static WSNs do. A real
  receiver — even bolted to a pole — reports a slightly *jittering* lat/lon over
  time (receiver noise / atmospheric wander / DOP), NOT motion.

These are orthogonal: a pole-mounted WSN can have a perfectly live, time-varying
gpsd fix. The jitter is noise, not travel. This split matters for both which
source is authoritative (below) and how the live path can be TESTED (§6).

- **What it is:** `wes-gps-server` — a WES Deployment exposing plain **gpsd** on
  the standard port **2947** (observed: gpsd **3.17**, JSON protocol). In-cluster it
  resolves at `wes-gps-server.default.svc.cluster.local:2947`; the pod IP is also
  directly routable on the flannel pod network (`10.42.0.0/24` via `cni0`) from the
  node host (§6.1). On connect gpsd emits a `VERSION` banner, then after
  `?WATCH={"enable":true,"json":true};` streams `TPV` (position) and `SKY`
  (satellite/DOP) objects. `WES_GPS_SERVER_SERVICE_HOST` confirms the service is
  registered cluster-wide.
- **Position only — never identity.** gpsd yields `lat`/`lon`/`alt`, a `mode`
  (0 unknown / 1 no-fix / 2 = 2D / 3 = 3D), fix `time`, and (via SKY) satellite
  count + HDOP. It is NOT a source of `vsn`/`node_id`; those come from the manifest /
  WES env injection (§2.3). So gpsd fills only the location half of `NodeInfo`.
- **gpsd holds the serial device exclusively → the socket is the ONLY path.** On
  W09E the receiver is `/dev/ttyACM0` (= `/dev/gps`, u-blox 7, VID:PID
  `1546:01a7`); gpsd opens it with `-N -n` and a direct device read returns
  `Device or resource busy`. A plugin therefore cannot (and must not) read NMEA off
  the device itself — it must go through gpsd. This is a concrete argument for a
  library wrapper: the transport is fixed and non-obvious, exactly the knowledge
  that belongs in pywaggle2, not per-plugin.
- **pywaggle does NOT wrap it today.** Grep of pywaggle 0.56 for
  `gps|gpsd|2947|location` → zero hits; `from waggle.data.gps import GPS` is dead
  code (module absent). Wrapping the gpsd socket cleanly is therefore net-new work
  and precisely what `get_node_info()`'s live branch should own, so plugins never
  hand-roll a raw gpsd connection.
- **A static deployment may STILL have a live fix — and it's ignored for
  NodeInfo.** Some WSNs have no receiver (gpsd refuses — H00F's
  `wes-gps-server:2947` returned connection-refused); others have a live receiver
  that jitters. Either way, on a static DEPLOYMENT the authoritative location is
  the surveyed manifest coordinate (`gps_lat`/`gps_lon`), and any live-but-jittering
  gpsd fix is deliberately IGNORED for `get_node_info()` — otherwise two identical
  pole-mounted nodes would report subtly different, time-varying coordinates for a
  fixed asset, which is wrong for the "where is this node installed" question a
  consumer like BirdNET is asking. So the resolver must (a) not treat "gpsd
  unreachable" as an error, and (b) not prefer a present live fix over the surveyed
  coordinate on a static node. The DEPLOYMENT-mobility axis decides authority, not
  whether a fix happens to be available.

**How this binds to the mobility tri-state (§2.2):** the gpsd source is the
concrete mechanism behind the `mobility`-driven branching, which is what makes the
tri-state pay for itself:

- `mobility == "mobile"` → query `wes-gps-server` (gpsd) for a live fix;
  re-poll per `max_age`; fall back to manifest coords if no fix yet.
- `mobility == "static"` → the surveyed manifest coordinate is authoritative; read
  it once and cache for the plugin's life. Do NOT prefer a live gpsd fix even if
  one is being served (it would only add jitter to a fixed location).
- `mobility == "unknown"` → conservative: use manifest coords; attempt gpsd only
  best-effort, short-timeout, and never let its failure propagate as an error.

So `wes-gps-server` does not change the `NodeInfo` API — it is the data source
behind its live branch, and its fixed-vs-mobile behavior is the reason the
mobility tri-state and `max_age` caching exist rather than a blanket "always poll
GPS."

#### 2.2.2 Two tiers of GPS access — snapshot vs. live stream

There are two genuinely different GPS use cases, and pywaggle2 owns BOTH so that
vendor/transport knowledge (the gpsd port, JSON protocol, reconnect logic) never
leaks into plugin code (the §1.4 principle applied to GPS):

- **Tier 1 — snapshot: `get_node_info()`.** "Where/what am I, roughly, right now."
  Identity (`vsn`/`node_id`) + a point-in-time location + `mobility`. This is what
  the overwhelming majority of plugins want, including **BirdNET**: it needs a
  single lat/lon at startup to self-configure its geo/seasonal species filter, not
  a position feed. One call, cached per §2.2, done.

- **Tier 2 — live stream: `gps_stream()` / `waggle.data.gps.GPS().watch()`.** A
  continuous position feed for the rare plugin on a mobile node that needs
  high-rate updates (a moving-vehicle tracker, a drone-mounted imager tagging each
  frame with its own changing position). This is a thin library wrapper over the
  `wes-gps-server` gpsd socket (§2.2.1): it yields successive `Fix` objects as an
  iterator/generator, handling connect, the `VERSION` banner, `?WATCH` enable,
  gpsd-JSON parse, timeout, and reconnect internally. A `Fix` surfaces the fields
  gpsd actually provides — `lat`, `lon`, `alt`, `fix_time` (from TPV) and
  `mode` (2D/3D/no-fix), plus optional quality (`hdop`, `n_sats_used`) merged from
  the adjacent SKY report so a plugin can gate on fix quality. Shape (illustrative):

  ```python
  from waggle.data.gps import GPS
  for fix in GPS().watch():          # blocks, yields each new TPV fix
      if fix.mode >= 2:              # 2 = 2D, 3 = 3D; skip no-fix
          tag_frame(fix.lat, fix.lon, fix.fix_time)
  # or a bounded/best-effort single read:
  fix = GPS().read(timeout=5)        # -> Fix | None
  ```

  On a node with no live fix (no receiver — gpsd refuses/empty, e.g. H00F)
  `watch()` yields nothing and `read()` returns None; the wrapper NEVER fabricates
  and never raises on "no GPS hardware," so a plugin can attempt it best-effort and
  fall back to `get_node_info()` manifest coords. NOTE the observed jitter: even a
  fixed receiver's successive fixes wander at the ~1e-7–1e-6° level (§6.1), so a
  consumer that wants a stable point should average/median a short window rather
  than trust a single reading — a helper (`GPS().read_averaged(n, timeout)`) is a
  reasonable convenience but not required for v1.

**How a plugin chooses between the tiers:** via `NodeInfo.mobility`. The
recommended pattern is "resolve once, then stream only if it's worth it":

```python
info = Plugin.get_node_info()
if info.mobility == "mobile":
    for fix in GPS().watch():      # live positions matter on this node
        ...
else:                              # "static" or "unknown"
    use(info.lat, info.lon)        # one fixed location is all there is
```

**Raw gpsd is the escape hatch, not the recommended path.** Nothing prevents a
plugin from opening `wes-gps-server:2947` itself, but it should not have to — if
`gps_stream()` is missing a knob a real plugin needs, the fix is to extend the
library accessor, not to document raw-socket access as the norm. Keeping the
mechanism in one place is the entire point of putting GPS in pywaggle2.

#### 2.2.3 Missing-value contract: sentinels, None, and normalization

pywaggle2 must degrade gracefully when it runs against a core stack that does NOT
yet set the new identity fields (an older WES, a lagging manifest, a partial
rollout). The rule: **never crash, never block, never fabricate — resolve to a
clean Python `None` (or the mobility `"unknown"` state) and let the
already-established "omit rather than fake" behavior take over.** Two design pieces
make this robust.

**(a) Wire sentinels — how "missing" is expressed on channels that have no null.**
Some transports can't represent "explicitly absent": a bare env var is either set
to a string or unset; an older JSON manifest may carry a stand-in rather than a
proper null. So the *wire* contract defines a findable sentinel per field:

| Field | Wire sentinel for "missing" | Why this value |
|---|---|---|
| `WAGGLE_NODE_MOBILITY` | unset / `"unknown"` | tri-state already has `"unknown"`; conservative default |
| `WAGGLE_NODE_VSN` | `0` | `0` is never a real VSN (real ones look like `W09E`, `H00F`) — unmistakable stand-in |
| `WAGGLE_NODE_GPS_LAT` / `_LON` | `999` | `0` is a VALID coordinate (Null Island, Gulf of Guinea) so it CANNOT be the sentinel; `999` is off-the-globe and trivially greppable |

The intent is that WES sets **real** values; the sentinel is only the fallback a
lagging producer may emit so downstream code has an obvious, non-crashing signal.

**(b) Normalization at the API boundary — pywaggle2 accepts BOTH sentinel and
real-None, and always returns None.** A field can arrive "missing" in three ways,
and pywaggle2 collapses all three to the same clean result:

1. **Wire sentinel** — `VSN=0`, `lat/lon=999`, `MOBILITY` unset.
2. **Genuinely absent** — env var unset, manifest key missing.
3. **Proper `None`/null** — a newer, correct WES explicitly sends null.

For each field pywaggle2 resolves the raw value, then **if it is absent OR equals
the wire sentinel OR is already None**, it sets the `NodeInfo` field to Python
`None` (and `location_source="unavailable"` for coordinates). A missing VSN simply
becomes `vsn=None` — no separate placeholder flag is needed, since `vsn is None`
already means "unresolved" (see §2.2.4 #3). So:

- **The plugin author NEVER sees `999` or `0`.** They see `None`. This preserves
  the core invariant (`if info.lat is not None:` → else omit EXIF GPS): a naive
  plugin literally cannot write `999` into a geotag, because it never receives 999.
  Passing the sentinel through would be *worse* than Null Island — a garbage
  coordinate that looks intentional.
- **Sentinel-in and None-in are equivalent inputs; None is always the output.**
  pywaggle2 doesn't care whether the far side is old (sentinel), silent (absent),
  or new (real null) — the normalizer converts all of them. That is the graceful-
  degradation guarantee: correctness does not depend on which core version is
  underneath.
- **`mobility` is the one field that resolves to a value, not None**: absent or
  unrecognized → `"unknown"` (the conservative tri-state member), never None, so
  callers can always branch on it.

This makes the sentinel purely a *wire convenience* and `None` the *API truth*.
The two are complementary, not competing: the wire sentinel keeps null-less
channels expressive; the normalization layer restores Pythonic absence at the
boundary.

#### 2.2.4 Resolved design decisions (identity/GPS)

These were reviewed and DECIDED (2026-07-08):

1. **Lat/lon sentinel is the literal `999`.** Valid ranges are lat `[-90, 90]` and
   lon `[-180, 180]`; `999` is well outside both, so it is unmistakable and never
   collides with a real coordinate. The normalizer parses the string form and
   treats `999` (i.e. `999`, `"999"`, `"999.0"`) as "missing" → `None`. It also
   defensively rejects any value that parses out of the valid range (lat outside
   `[-90, 90]` or lon outside `[-180, 180]`) as missing, but `999` is the
   documented, canonical sentinel producers should emit.
2. **VSN "missing" set is broad.** `0`, `"0"`, and `""` (empty) all normalize to
   `vsn=None`. Any of them means "no real VSN."
3. **`NodeInfo` exposes `location_source`, NOT a placeholder flag.** `location_
   source` (`"gps-live"` | `"manifest"` | `"unavailable"`) stays — it carries
   distinct information `None` alone cannot express. `vsn_is_placeholder` is DROPPED:
   with VSN normalized to `None` when unresolved (#2, #4), `vsn is None` already
   means "unresolved," so a separate flag is redundant and invites drift. (Note:
   image-sampler2's `nodemeta.py` still carries `vsn_is_placeholder` because it
   substitutes a visible `"NODE"` string for the filename; when its logic is hoisted
   into pywaggle2 that behavior changes to None-when-missing and the flag is
   removed — a plugin that wants a filename token supplies its own stand-in.)
4. **`get_vsn()` returns `None` when VSN is missing** (matches the normalization
   philosophy). Callers that need a filename token choose their own stand-in.
5. **Env vars are the primary source; mounted manifest is the fallback.** Prefer
   `WAGGLE_NODE_*` env (simplest, no mount, works for non-Python consumers); fall
   back to a mounted `node-manifest-v2.json` only when the env is absent.
6. **gpsd host/port via `WAGGLE_GPS_SERVER` env, default to the DNS name.**
   pywaggle2 reads `WAGGLE_GPS_SERVER` (host:port) if set, else defaults to
   `wes-gps-server.default.svc.cluster.local:2947` — so the library isn't
   hard-coded to one resolution path (and host-side testing can point it at a
   discovered pod IP).

With these decided, the identity/GPS API shape is locked; see §7.1 for what
remains to wrap up the overall design.

### 2.3 Requires a WES side (documented here, filed under Infra #1)

For the API to have data to return (and for non-Python plugins), WES must inject
node identity into every pod — as env vars (`WAGGLE_NODE_VSN`, `WAGGLE_NODE_ID`,
`WAGGLE_NODE_GPS_LAT`, `WAGGLE_NODE_GPS_LON`, **`WAGGLE_NODE_MOBILITY`**) and/or
by reliably mounting `node-manifest-v2.json` at a documented in-pod path.
pywaggle2's accessor reads whichever WES provides and normalizes per §2.2.3: when
a field is unset, sentinel-valued, or null it resolves to `None` (mobility →
`"unknown"`). The intended-vs-fallback wire values WES should emit:

| Env var | Real value | Sentinel if unavailable |
|---|---|---|
| `WAGGLE_NODE_VSN` | e.g. `W09E` | `0` |
| `WAGGLE_NODE_ID` | e.g. `000048B02DD3C454` | unset |
| `WAGGLE_NODE_GPS_LAT` | e.g. `41.8681` | `999` |
| `WAGGLE_NODE_GPS_LON` | e.g. `-87.6134` | `999` |
| `WAGGLE_NODE_MOBILITY` | `static` \| `mobile` | unset (→ `unknown`) |

(The CI team indicated 2026-07-06 they intend to add runtime "GPS call" and "VSN
call" APIs — this doc pins the requirement + the desired shape so the API can be
reviewed. If their "GPS call" is itself a gpsd wrapper, §2.2.1/§6.3, pywaggle2
wraps the same source rather than double-wrapping.)

**Location resolution precedence (what `NodeInfo.lat/lon` returns).** With the
above sources, and driven by the `mobility` axis:
- `mobility == "mobile"` → try gpsd live fix; if present & valid use it
  (`location_source="gps-live"`); else fall back to injected/manifest coords
  (`"manifest"`); else `None` (`"unavailable"`).
- `mobility == "static"` → the surveyed manifest/injected coordinate is
  authoritative (`"manifest"`); do NOT consult gpsd even if it is serving a fix
  (that live jitter is noise for a fixed asset — the W09E finding, §2.2.1).
- `mobility == "unknown"` → conservative: prefer manifest/injected coords; try
  gpsd only best-effort if coords are absent; never error. Absent everywhere →
  `None`.

gpsd being absent is NEVER an error — it just means "no live tier, use the fixed
tier." (On a static node gpsd is skipped on PURPOSE; on a mobile node it is skipped
only when absent/no-fix.) The Tier-2 `GPS().watch()`/`read()` stream (§2.2.2) is a
SEPARATE consumer of the same gpsd — a mobile plugin wanting the continuous feed
calls `GPS()` directly; `NodeInfo` uses gpsd only to fill the one-shot location
snapshot.

**Manifest gap to close (companion ask, Infra #1).** As of 2026-07-08 the
manifest carries NO mobility signal. Verified against the live fleet (234 nodes,
`api.sagecontinuum.org/production`) and the on-node `node-manifest-v2.json`:
- `node_type` is only `WSN` (175) / `Blade` (59) — form factor, not mobility.
- `modem` is ~50/50 true/false — backhaul type (cellular vs wired); many FIXED
  rural nodes have a cellular modem, so `modem` is NOT a mobility proxy.
- `gps_lat`/`gps_lon` are static surveyed coordinates; no velocity/fix_time.
- `node-manifest-v2.json` has an unused `tags: []` array and no
  `is_mobile`/`mobility`/`node_class` field.

So mobility must be ADDED as an explicit, authoritative deployment property. Lean:
a top-level `mobility: "static" | "mobile"` field on `node-manifest-v2.json`
(cleaner and less ambiguous than a `tags: ["mobile"]` convention), defaulting to
`static` for the current fleet (all nodes are fixed today; mobile nodes are
planned). WES then injects it per the env/mount above. This rides along on the
same runtime identity injection the CI team is already adding — specifying it now,
before that API is finalized, is why it's worth raising today.

---

## 3. Other pywaggle2 enhancements distilled from Infra-problems-to-fix

These are the items that are genuinely pywaggle-domain (library concerns), as
opposed to build/registry/node-network issues. §3.1–3.4 distill directly from the
running Infra-problems-to-fix list; §3.5–3.6 come from the local-cache design work
and the WES/SES source reading (2026-07-08) and are pywaggle-domain by the same
"belongs in the shared library, not per-plugin" test.

### 3.1 Modern, self-contained, pip-installable (Infra #5 base-image gotcha)

`waggle/plugin-base` tops out at `1.1.1-base` (no newer `-base`), shipping **Python
3.8.5** and an OLD **pywaggle 0.40.7** whose `Plugin` has NO `upload_file` (only
get/publish/subscribe/init/stop) and no piexif. You cannot "get a newer base
image"; you must `pip install pywaggle[vision]==0.56.*` on top and keep code
Python-3.8-compatible. pywaggle2 should:
- Target a **modern Python** (3.12+), decoupled from the stale base image.
- Be cleanly `pip install`-able with sane extras: a LIGHT core (publish/subscribe/
  upload/node-info, pure-Python, no OpenCV/numpy) and an optional `[vision]` extra
  that pulls the heavy decode stack ONLY when a plugin needs pixels. image-sampler2
  proved the light core is enough for a raw-still + inject + upload plugin — no cv2.
- Guarantee `upload_file(...)` (with `timestamp=` override) and the metadata-inject
  helper are in the CORE, not gated behind [vision].

### 3.2 Credential handling in the library, not per-plugin argv (Infra #10)

Existing plugin job YAMLs embed camera credentials directly in argv (the
`--snapshot-url http://user:pass@host/...` anti-pattern), which leaks into process
listings, logs, and `git`. pywaggle2's `Camera` should:
- Read camera credentials from the ENVIRONMENT (e.g. `CAMERA_USER`/
  `CAMERA_PASSWORD`, or a WES-provided secret), NEVER require them in the URL/argv.
- REDACT credentials in every log line it emits (`password=***`).
- For named cameras, get credentials from the WES data-config/secret, so the job
  YAML never carries them. This is the env-only pattern image-sampler2 already uses;
  pushing it into the library makes it the default for all plugins.

### 3.3 Geo-filtering support falls out of node-info (Infra #11)

BirdNET-style geo/seasonal filtering is silently disabled without coordinates,
producing implausible results (European warblers at a Chicago feeder). This is not
a separate feature — it is a direct consequence of #2 (no runtime location). Once
`get_node_info()` returns real lat/lon, geo-filtering plugins can self-configure
per node from one portable job YAML. pywaggle2 should document this as the intended
consumer of node-info and (optionally) offer a small helper to compute
location/season context. No hard-coded `--lat/--lon` per node across ~100 nodes.

### 3.4 Capture-time & upload-time contract (already partly in 0.56, make explicit)

pywaggle 0.56 `upload_file(timestamp=capture_ts)` correctly overrides the default
grab time, and the object key is `<ts>-<sha1>`; all `meta` values must be strings.
pywaggle2 should make the two-clock model first-class and documented: a
CAPTURE/exposure time (camera-side when available per 1.5, else node grab-time) AND
a distinct UPLOAD time, both recorded, never conflated. (image-sampler2 verified
this end-to-end: record timestamp = original capture ts, `upload_timestamp` =
distinct later send time.)

### 3.5 Shared local cache primitive (the producer/consumer counterpart to upload)

pywaggle2 should provide a CORE shared-cache primitive
(`cache_file()`/`read_cache()`) beside `upload_file()`, so plugins can implement
the producer/consumer pattern (one plugin fills a node-local ring, another reads
it) the same way they upload. This is the LIBRARY (Layer-1) half of a two-layer
design; the platform (Layer-2 hard-quota backstop via a `wes-local-cache-manager`
pod) and the node-persistent mount are the WES half. pywaggle2 owns: cache-root
resolution (`$WAGGLE_LOCAL_CACHE → /local-cache → /tmp` dev fallback), the
ts-prefixed filename layout, GRACEFUL plugin-owned eviction (count/MB/LRU — the
plugin's semantics), cross-user-read chmod-on-write, and optional cache
announcement. image-sampler2's `cache.py` is the working reference to hoist.

`read_cache()` is the consumer side: it returns the CACHED FILES for a producer
unit, newest-first, as lightweight handles (`path`, `capture_ts` parsed from the
ts-prefixed name, `size`), NOT decoded bytes — the consumer picks which to open.
The default selects the single newest entry; an optional time-window / count
selector narrows it (e.g. "frames in the last N seconds", "newest K"). This
mirrors image-sampler2's `--from-cache` newest-first behavior; the richer
time-window selectors are DEFERRED there and specified in full in local-cache-
design.md rather than here (this doc only pins the API shape).
FULL DESIGN: `~/AI-projects/local-cache-design.md` (§3 = this library primitive;
§4 = the WES manager pod; §1.4 = why hostPath needs a purpose-built quota).

### 3.6 Uploads-and-cache write both under WES-provided host paths

Note the platform reality both primitives depend on (verified from
`edge-scheduler`/`waggle-edge-stack` source, 2026-07-08): `/uploads` is a shared
hostPath (`/media/plugin-data/uploads/<job>/<plugin>/<tag>`) drained by the
`wes-upload-agent` DaemonSet. `/local-cache` should mirror this exactly (sibling
`/media/plugin-data/local-cache` tree + a manager DaemonSet). pywaggle2's job is to
present clean `upload_file`/`cache_file` APIs over whichever host paths WES mounts.

---

## 4. Explicitly OUT of scope for pywaggle2

These Infra items are real but belong to OTHER components, not the client library —
listed so this doc's scope stays honest:

- **#2 ECR buildkit `/proc/acpi` runc failure** — builder-host infrastructure
  (filed: waggle-edge-stack#110).
- **#3 arm64 NVIDIA QEMU build crash**, **#4 registry push auth**, **#6 lan0/node
  registry down**, **#7 control-plane stale after reboot** — ECR pipeline / node
  network / WES ops.
- **#8 data-API `meta.task` vs `meta.job`**, **#9 pluginSpec volume-mount schema**
  — data-API / scheduler docs & schema.
- **#12 `pluginctl run` namespace bug**, **#13 `--node` vs `--selector` scheduling**
  — pluginctl / scheduler.

pywaggle2 depends on the WES side of #1 (identity injection) to have data to
return, but the library API itself is in scope; the WES injection is tracked under
Infra #1.

---

## 5. Migration & compatibility

- **Drop-in `Camera` / `Plugin`**: keep the existing call shapes
  (`with Plugin() as p`, `Camera(name).snapshot()`) so existing plugins upgrade by
  bumping the dep, gaining the acquisition ladder + node-info without code changes.
- **Additive `snapshot()` result**: `.data` (pixels) stays for ML plugins;
  `.raw_bytes` / `.acquisition_path` / `.camera_capture_time` are new, optional.
- **New calls are additive**: `get_node_info()`, `get_vsn()`, `get_location()`,
  and the live-stream tier `gps_stream()` / `waggle.data.gps.GPS().watch()`
  (§2.2.2). All new; nothing existing changes shape.
- **Reference implementation exists**: image-sampler2 already implements the
  still-first acquisition + EXIF-inject + two-clock + env-only-creds +
  never-fabricate-identity patterns for Reolink. pywaggle2 generalizes these
  (add Hanwha SUNAPI + Mobotix native-still builders, the MJPEG-RTSP rung, and the
  OpenCV floor) and moves them into the shared library.

---

## 6. Open questions / verification needed (some need real hardware)

1. Do the WSN Hanwha cameras (XNV-8081Z / XNF-8010RV) have an **MJPEG profile
   configured** so the SUNAPI snapshot returns a JPEG rather than erroring? If not,
   is enabling one acceptable, or do we rely on decode-from-H.264 for them?
2. What metadata does a real **Hanwha snapshot actually carry** (marker-scan an
   XNV-8081Z/XNF-8010RV still)? Camera-metadata ref lists Hanwha EXIF as "likely,
   unverified on a Sage unit." Confirms whether preservation is worth it for this
   vendor (as it clearly is for Mobotix).
3. Final **node-info API shape** — align with whatever the CI team's "GPS call" /
   "VSN call" turns out to be, so pywaggle2 wraps rather than competes. (Note their
   "GPS call" may itself just wrap `wes-gps-server` gpsd :2947 per §2.2.1 — worth
   confirming so pywaggle2 wraps the same source and doesn't double-wrap.)
4. Where should the **snapshot-URL / MJPEG-availability** advertisement live for
   NAMED cameras — extend `data-config.json`, or a companion capability file?

### 6.1 GPS testing — what's actually blocked vs. testable now

Because deployment-mobility and GPS-fix-liveness are orthogonal (§2.2.1), the
gpsd/live-stream path is NOT gated on owning a mobile node:

- **TESTABLE NOW — the Tier-2 `gps_stream()` / `GPS().watch()` mechanism.** Any
  static WSN that has a GPS receiver serving gpsd is a valid rig: a pole-mounted
  receiver still emits successive, slightly-differing TPV fixes (jitter), which
  exercises the entire wrapper — connect → gpsd-JSON parse → stream of changing
  fixes → timeout/reconnect. The jitter being noise rather than travel is
  irrelevant to verifying the code path. NEXT STEP: find a fleet WSN whose
  `wes-gps-server:2947` actually serves fixes (H00F refused — it has no receiver),
  and validate `watch()`/`read()` against it. This closes the "streaming path is
  unexercised" gap without any mobile hardware.

  **PARTIALLY CONFIRMED on real hardware (2026-07-08).** Probed W09E/W08B/W06C/W0A4
  via the `waggle-dev-node-<vsn>` gateway. All four carry a real GPS receiver in
  the manifest — **Geekstory VK-162 USB dongle, `is_active: true`, scope nxcore** —
  and on W08B a **live gpsd process was directly observed** inside the gps-server
  pod (`/usr/sbin/gpsd -N -n -G -D 5 /host/dev/gps`, running as `nobody`, up weeks,
  actively consuming CPU; physical dongles present at `/dev/ttyACM0`,
  `/dev/ttyUSB0-4`). So a pole-mounted static node WITH a live, jittering gpsd fix
  is real and present in the fleet — the test rig exists. Manifest surveyed coords:
  W08B `41.822952,-87.609693`; W06C `43.940154,-110.644137`; W0A4
  `41.701598,-87.995233`; **W09E is unsurveyed (`gps_lat/lon = null`)** — a useful
  edge case for the "location genuinely unknown → return None, omit EXIF GPS" rule.
  Access note: the gateway login (`ssh waggle@waggle-dev-node-<lowercase-vsn>`) is
  plain `waggle` with NO passwordless sudo on these older NX nodes (unlike the
  `beckman` sudoers account on H00F), so kubectl / docker / pod-exec / nsenter are
  all closed — but a live read did NOT require them (see below).

  **CONFIRMED — live TPV stream captured (2026-07-08 23:41 UTC, W09E).** Read gpsd
  directly WITHOUT root: the gps-server pod's IP on the flannel pod network
  (`10.42.0.128:2947`, discovered via `ip neigh` on the `10.42.0.0/24` `cni0` net)
  is routable straight from the host, so no kubectl/sudo was needed after all — just
  a plain socket from the `waggle@waggle-dev-node-w09e` shell. GPS device is
  `/dev/ttyACM0` = `/dev/gps`, u-blox 7 (VID:PID `1546:01a7`); gpsd holds it
  exclusively (`Device or resource busy` on direct read), so the socket is the only
  path — validating that a library wrapper (not raw device reads) is the right
  design. gpsd 3.17, JSON proto. Fix: **3D, 16 sats seen / 10 used, HDOP 0.81**,
  ~`41.8681329, -87.6133953`, alt ~188 m. Over 8 TPV fixes in ~2 s the position
  **jittered at the 1e-7–1e-6° level (≈cm–2 m)** with zero physical motion —
  demonstrating the two-axes point on real hardware: a STATIC pole node emits a
  live, time-varying fix. Crucially W09E's **manifest `gps_lat/lon` is null
  (unsurveyed)** while gpsd serves a good drifting fix — the exact case the
  "static → manifest authoritative, ignore live jitter" rule (§2.2.1) is designed
  for. The full Tier-2 contract (connect → VERSION banner → `?WATCH` → TPV/SKY
  stream → close) was exercised end-to-end. Streaming path is no longer
  unexercised.
- **STILL BLOCKED — deployment-mobility SEMANTICS.** What genuinely needs real
  mobile hardware is a node reporting `mobility == "mobile"` with a fix that MOVES
  (meters-to-km of real travel, not centimeter jitter), plus the `mobility`
  manifest field being populated non-`static`. That validates the
  authoritative-source switch (manifest vs. live) and the `max_age` re-poll cadence
  under real motion. No such node exists yet (all 234 are static deployments), so
  this remains deferred until mobile nodes ship.

---

## 7. Status & next step

DRAFT for discussion; the acquisition and node-info designs are stable, the API
shapes are pinned, and the GPS source is now **empirically confirmed** — a live TPV
stream was read from `wes-gps-server` gpsd on W09E (§2.2.1, §6.1), validating the
two-axes model and the "static → manifest authoritative" rule on real hardware.

The time-critical piece remains §2 + §6.3: the CI team is actively building runtime
"GPS call" / "VSN call" APIs (indicated 2026-07-06), so the highest-leverage next
step is to circulate §2 (node-info API + the mobility tri-state and the `mobility`
manifest-field ask) and §6 open-Qs with them BEFORE their identity API freezes — so
pywaggle2 wraps it rather than competes. §1 (acquisition ladder) and §3 (library
enhancements) can follow as a fuller upstream RFC to `waggle-sensor/pywaggle`,
anchored by image-sampler2 as the reference implementation.

### 7.1 Remaining work to "wrap up" the design

1. **Circulate §2 + §6 with the CI team NOW** (the only item with an external
   clock). Confirm their forthcoming "GPS call" is itself a gpsd wrapper (§6.3) so
   pywaggle2 wraps the same source; get the `vsn`/`node_id`/`mobility` env-injection
   names (§2.3) agreed; float the `mobility` manifest-field ask before the identity
   API freezes.
2. **Camera-side hardware verification** (§6.1–6.2, needs a reachable Hanwha):
   does the WSN Hanwha expose an MJPEG snapshot profile, and what EXIF does its
   still carry? These are the last unknowns gating the §1 acquisition ladder; until
   then the H.264-decode floor is the safe default for Hanwha.
3. **Decide the two small open API knobs**: the `read_averaged()` GPS convenience
   (§2.2.2 — jitter smoothing, optional) and the snapshot-URL/MJPEG advertisement
   home for named cameras (§6.4 — extend `data-config.json` vs. companion file).
4. **Nothing else needs real motion.** The only genuinely hardware-blocked item is
   deployment-mobility SEMANTICS (§6.1) — a node that actually moves — which waits
   on mobile nodes shipping and does not block v1.
5. **Then: promote DRAFT → RFC.** Split into the two natural deliverables — a short
   §2/§6 note for the CI team's identity work (soon), and the fuller §1/§3 upstream
   RFC to `waggle-sensor/pywaggle` anchored by image-sampler2.

The design itself is essentially complete: every API shape is pinned and the two
hardware-verifiable premises we could reach (metadata-preserving still path on
Mobotix; live gpsd on a static node) are both confirmed. What's left is
coordination (item 1), a camera probe (item 2), and two minor decisions (item 3) —
not further design.
