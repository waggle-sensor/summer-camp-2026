# Getting a node's GPS / location (and VSN) inside a plugin

Durable platform facts confirmed on H00F (fixed node, Thor) June-July 2026.

## VSN is ALSO unavailable at runtime — and you usually don't need it
The exact same situation as GPS applies to the node VSN (e.g. "H00F"): pywaggle
0.56 has no VSN accessor, no pod env var carries it, and `/etc/waggle/vsn` (like
the manifest) is a HOST path NOT mounted into pods. So a plugin cannot self-report
its VSN inside a pod either.
KEY REALIZATION (verified July 2026 via a full Beehive round-trip): the plugin
does NOT need to. **Beehive attaches node identity (vsn, node) DOWNSTREAM via
message routing.** An `image-sampler2` upload whose FILENAME used a placeholder
vsn "NODE" came back from the data API with `meta.vsn=H00F,
meta.node=00004cbb4701d16c` — correct attribution with zero help from the plugin.
The existing yolo/bioclip plugins likewise never self-identify. So: do NOT block
an upload on missing VSN/GPS.

## Placeholder pattern (use until the runtime GPS/VSN calls ship)
When identity can't be resolved and you still need something in the FILE itself:
- VSN -> a clearly-marked PLACEHOLDER (e.g. "NODE", overridable by env), flagged
  as placeholder, with a WARNING logged. Never fatal.
- lat/lon -> OMIT from EXIF. NEVER fabricate coordinates — fake geo corrupts
  science data; absent is correct.
Keep the runtime lookup behind ONE clearly-marked swap-in point (grep-able tag
like `TODO(sage-ci)`) so it's a one-function change when the CI team ships the
runtime "GPS call" + "VSN call" APIs (planned mid-2026). image-sampler2's
`nodemeta.py::_runtime_identity()` is the reference implementation of this shape.

See also `~/AI-projects/Infra-problems-to-fix.md` (issue #1) for the issue-ready
writeup of the runtime-identity gap.

## pywaggle has NO location/GPS accessor (as of pywaggle 0.56)
- `src/waggle/` contains only two submodules: `data` (audio, vision) and
  `plugin` (publish/subscribe/protocol). There is **no** `waggle.data.gps`,
  no `Plugin.get_location()`, no location API at all.
- Do NOT write `from waggle.data.gps import GPS` — that import always fails.
  (It silently returns None in a try/except, i.e. dead code that looks alive.)

## The mechanisms that DO exist, in order of practicality
1. **Node manifest file** `/etc/waggle/node-manifest-v2.json` on the HOST.
   Contains `gps_lat` / `gps_lon` (+ `vsn`, `name`). The platform maintains it.
   CONFIRMED: H00F manifest had valid coords (41.7180, -87.9827).
   PITFALL: SES does **NOT** mount this file into plugin pods. A plugin
   container sees no `/etc/waggle/` (verified: bare `docker run` and a real
   `ses`-namespace pod both report the path missing). So reading the manifest
   path from inside a pod fails unless you arrange a mount yourself — and the
   standard Waggle job pluginSpec schema does not expose hostPath/volume mounts
   (no existing job YAML in our repos uses them).
2. **`wes-gps-server` — plain gpsd on port 2947 (the standalone live-fix
   service).** Distinct from the `sys.gps.*` data-plane stream below: WES runs a
   dedicated GPS service as its own k8s **Deployment**, reachable in-cluster at
   `wes-gps-server.default.svc.cluster.local:2947`, speaking the standard gpsd
   JSON protocol (`?WATCH={"enable":true,"json":true};` → `TPV` reports carrying
   `lat`/`lon`/`alt`/`time`). Registered cluster-wide (the
   `WES_GPS_SERVER_SERVICE_HOST` env var appears in SYSTEM pods like
   device-labeler — but NOT in plugin pods). VERIFIED FACTS (2026-07):
   - Position ONLY — never vsn/node_id. It fills half of a NodeInfo at most.
   - pywaggle does NOT wrap it (0.56 grep `gps|gpsd|2947|location` → 0 hits). A
     plugin today would hand-roll a raw socket — which is exactly why the wrapper
     belongs in the library (see the two-tier design below), not per-plugin.
   - On a FIXED node it REFUSES connections (no GPS receiver) — probing H00F's
     `wes-gps-server:2947` returned connection-refused. That is EXPECTED, not a
     fault; fixed-node coords live in the manifest, not gpsd. So never treat
     "gpsd unreachable" as an error on a static node.
3. **Live `sys.gps.*` measurement stream.** GPS-equipped / mobile nodes run a
   GPS device plugin that publishes `sys.gps.lat` / `sys.gps.lon`. A plugin
   reads them by subscribing on the data plane:
   ```python
   with Plugin() as plugin:
       plugin.subscribe("sys.gps.lat", "sys.gps.lon")
       msg = plugin.get(timeout=...)   # msg.name / msg.value
   ```
   PITFALL: fixed nodes have NO GPS publisher, so this never yields a fix
   there. Make it OPT-IN (e.g. a `--gps-subscribe` flag, default off) so you
   don't add seconds of startup / a broker connect on every run for nodes that
   can't benefit. Confirmed: H00F has no `sys.gps.*` records in the data API.
4. **Env vars** (e.g. `WAGGLE_NODE_GPS_LAT/LON`) — not set by SES today on
   fixed nodes, but cheap to check as a fallback in case a deployment injects
   them.

## Recommended plugin pattern (hybrid resolver)
Resolve coordinates at runtime, first source that succeeds:
`manifest file (several probed paths) -> env vars -> (opt-in) live sys.gps.*`.
Always let explicit `--lat/--lon` CLI args override everything. If nothing
resolves, log clearly and disable geo-filtering rather than crashing.

## Practical bottom line on Sage TODAY
On a fixed node NONE of the auto sources work inside the pod. Two acceptable
responses depending on what you need:
- If the value only affects node ATTRIBUTION (which node produced the data):
  do nothing — let Beehive stamp vsn/node downstream (see the placeholder section
  above). This keeps the plugin fleet-portable with zero per-node config.
- If the value must be IN THE FILE (EXIF geotag, geo-filtering like BirdNET):
  pass `--lat/--lon` (and `--vsn` if needed) explicitly in the job YAML from the
  host manifest, OR use the placeholder + omit-GPS fallback until the runtime
  calls exist. Keep the hybrid resolver in code for portability/mobile nodes, but
  don't expect it to fire on fixed nodes.

## The "proper" fix belongs upstream (worth filing)
- pywaggle: add a first-class location accessor (mirrors
  `waggle.data.audio.Microphone` / `.vision.Camera`) returning
  (lat, lon, alt, fix_time); live fix on GPS nodes, manifest fallback on fixed.
- waggle-edge-stack / WES: inject node GPS (manifest coords + live fix) into
  every plugin pod's env, and/or reliably mount the manifest at a documented
  in-pod path — so non-Python plugins work without an API call.

### Two tiers of GPS access — snapshot vs. live stream (pywaggle2 design, 2026-07-08)
There are two genuinely different GPS use cases; the library should own BOTH so
the gpsd port/protocol/reconnect logic never leaks into plugin code (same "vendor
knowledge belongs in the library" principle as the camera acquisition ladder):

- **Tier 1 — snapshot: `get_node_info()`.** "Where/what am I, roughly, right now":
  vsn/node_id + a point-in-time location + mobility. Cached (see caching contract
  above). This is what ~95% of plugins want, INCLUDING BirdNET — it needs one
  lat/lon at startup for its geo-filter, not a feed.
- **Tier 2 — live stream: `gps_stream()` / `waggle.data.gps.GPS().watch()`.** A
  continuous position feed for the rare mobile-node plugin needing high-rate
  updates (vehicle tracker, drone imager tagging each frame). A thin library
  wrapper over the `wes-gps-server` gpsd socket that yields successive fixes
  (`lat`/`lon`/`alt`/`fix_time`), handling connect/parse/timeout/reconnect
  internally. On a node with no live fix (any static node) `watch()` yields
  nothing and `read(timeout=)` returns None — NEVER fabricates, never raises on
  "no GPS hardware," so a plugin can attempt it best-effort and fall back to
  `get_node_info()` manifest coords.

**How a plugin picks the tier:** via `NodeInfo.mobility`. Recommended pattern —
"resolve once, then stream only if it's worth it":
```python
info = Plugin.get_node_info()
if info.mobility == "mobile":
    for fix in GPS().watch(): ...        # live positions matter here
else:
    use(info.lat, info.lon)             # one fixed location is all there is
```
Raw gpsd (`wes-gps-server:2947`) is the ESCAPE HATCH, not the recommended path:
nothing stops a plugin opening the socket, but if `gps_stream()` lacks a knob a
real plugin needs, extend the accessor — don't document raw-socket access as the
norm. NB: the `watch()`/`read()` shapes are design, UNVERIFIED against a live fix
— there is no mobile node in the fleet yet (all 234 are static), so the streaming
path can't be exercised on real hardware until mobile nodes exist.

### NodeInfo design refinements (pywaggle2 RFC, 2026-07-08)
The upstream `get_node_info()` accessor should carry MORE than lat/lon/vsn:

- **`mobility` as a TRI-STATE, not a bool: `"static" | "mobile" | "unknown"`.**
  A plugin needs to know whether re-polling location is EVER worthwhile. On a
  STATIC node coords never change → resolve ONCE at startup, never call again. On
  a MOBILE node (vehicle/drone) location changes → the plugin MAY re-poll on a
  science-driven cadence. `"unknown"` is a REAL, common state (old manifest, or
  injection unavailable) and must drive CONSERVATIVE behavior — do NOT collapse to
  a bool, which forces a static-or-mobile guess = latent bug. (`is_mobile()` may
  exist as a shim returning None for unknown; tri-state is authoritative.)
- **Semantic to document precisely:** `mobility=="mobile"` means "location is NOT
  fixed," NOT "moving right now." A parked vehicle-node is mobile yet stationary.
  The flag governs whether re-polling is ever warranted; the plugin owns cadence.
- **Caching contract that bakes in "resolve once on static":** give the accessor
  an optional freshness bound. `get_node_info()` = always fresh (force-refresh);
  `get_node_info(max_age=30)` = re-fetch the LIVE GPS only if `mobility=="mobile"`
  AND the cached fix is older than 30 s; for static/unknown returns cached forever
  (one resolve for the plugin's life). vsn/node_id/mobility are deployment-stable
  → always from cache after first resolve. This turns "ask once and be done" into
  a library property every plugin gets free, instead of per-plugin cache logic.

### The manifest has NO mobility signal today [fleet-verified 2026-07-08]
Surveyed the whole fleet (234 nodes, `api.sagecontinuum.org/production`) + the
on-node `node-manifest-v2.json`. There is NO mobility field, and the tempting
proxies are all red herrings:
- `node_type` = only `WSN`(175) / `Blade`(59) → FORM FACTOR, not mobility.
- `modem` = ~50/50 true/false → BACKHAUL type (cellular vs wired); many FIXED
  rural nodes have a cellular modem → NOT a mobility proxy.
- `gps_lat/gps_lon` = static surveyed coords; no velocity, no fix_time.
- manifest has an unused `tags: []` array and no `is_mobile`/`mobility` field.
=> Mobility must be ADDED as an explicit authoritative deployment property. Lean:
a top-level `mobility: "static"|"mobile"` on `node-manifest-v2.json` (cleaner than
a `tags:["mobile"]` convention), default `static` (all current fleet nodes are
fixed; mobile planned). WES then injects it (`WAGGLE_NODE_MOBILITY` env and/or the
mounted manifest); pywaggle2 reports `"unknown"` when absent. Specify this NOW,
before the CI team finalizes their runtime GPS/VSN API, so it rides along.

Public endpoints used for the survey (no auth): a single node's **rich** manifest is
`GET https://auth.sagecontinuum.org/manifests/<VSN>` (computes, sensors w/ camera
URIs + hw_model, gps, project); the flatter beta twin is
`GET https://auth.sagecontinuum.org/api/v-beta/nodes/<VSN>` (type, site, partner, focus, modem).
Fleet lists: `/manifests/` and `/api/v-beta/nodes/` (~2MB for full manifests — prefer per-VSN).
See `references/auth-api-manifests-and-nodes.md`. Both are handy for fleet-wide reconnaissance
without touching a node.

## BirdNET geo-filter specifics
`birdnet.load("geo","2.4","tf").predict(lat, lon, week=..., min_confidence=sf_thresh)`
builds a species set used to filter acoustic predictions. Without coords the
geo model is skipped and you match the GLOBAL species list — which surfaces
implausible species (European warblers/nightingale/magpie at a Chicago feeder).
Enabling geo-filtering both improves accuracy AND lets you safely lower the
detection threshold.
