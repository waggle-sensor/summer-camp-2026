# pywaggle2 NodeInfo + GPS API design decisions

Durable design contract for the proposed pywaggle2 library (next-gen pywaggle
client). Full doc: `~/AI-projects/pywaggle2-design.md`. This ref is the condensed,
reusable version of the identity/GPS half so future sessions don't re-derive it.
Companion ref: `node-ssh-access-and-gpsd-probe.md` (how to REACH gpsd; this ref is
how the API should WRAP it).

## Where the code goes (real pywaggle layout)
- `waggle/data/audio.py` = `Microphone` + `AudioSample(NamedTuple)`. This is the
  pattern to MIRROR. `waggle/data/vision.py` = `Camera`.
- NEW FILE `waggle/data/gps.py`: `class Fix(NamedTuple)` + `class GPS` with
  `.watch()` (generator yielding Fix) and `.read(timeout)` (-> Fix | None). Export
  from `data/__init__.py` so `from waggle.data.gps import GPS` works (that import is
  currently DEAD CODE in 0.56 — module absent).
- NEW METHODS on `class Plugin` (`waggle/plugin/plugin.py`, beside upload_file/
  timeit): `get_node_info(max_age=None) -> NodeInfo`, plus shims `get_vsn()`,
  get_location()`. `NodeInfo` = NamedTuple(vsn, node_id, lat, lon, alt, fix_time,
  location_source, mobility). NOTE: `vsn_is_placeholder` was DROPPED (see resolved
  decisions below) — `vsn is None` already signals unresolved.
- The resolver logic ALREADY EXISTS + is tested: image-sampler2
  `nodemeta.py::resolve_identity()` (+ `tests/test_nodemeta_stage3.py`, 13 pure
  tests). Hoist it; it does per-field precedence and never fabricates coords.

## Two-tier GPS (do NOT conflate)
- **Tier 1 — snapshot: `get_node_info()`.** "Where/what am I, roughly, now."
  Identity + point-in-time location + mobility. What ~95% of plugins want incl.
  BirdNET (one lat/lon at startup for its geo/season filter). Cached per max_age.
- **Tier 2 — live stream: `GPS().watch()`/`.read()`.** Continuous feed for the rare
  MOBILE-node plugin. Thin wrapper over the gpsd socket. Raw gpsd is the ESCAPE
  HATCH, not the recommended path — extend the wrapper instead of documenting
  raw-socket use.
- NodeInfo uses gpsd INTERNALLY only to fill the mobile-node location snapshot; the
  Tier-2 stream is a SEPARATE consumer of the same gpsd.

## mobility tri-state: "static" | "mobile" | "unknown"
- `mobile` = location NOT fixed = can change position WITHOUT significant human
  intervention (vehicle/drone mount). It says NOTHING about instantaneous motion —
  a mobile node parked 3 days is still `mobile`; the flag can't tell you if it's
  moving right now. `static` = cannot move without a deliberate physical reinstall.
- `unknown` is a real, common state (old manifest / lagging injection). Must drive
  CONSERVATIVE behavior — never coerce to a static-or-mobile guess. Absent/unknown
  mobility resolves to `"unknown"`, never None (so callers can always branch).
- `max_age` caching: static -> resolve once, live GPS hit at most once ever;
  mobile -> re-poll live GPS if cached fix older than max_age. Bakes "ask once on
  static" in so plugin authors don't have to.

## Location resolution precedence (what NodeInfo.lat/lon returns)
- mobile  -> try gpsd live fix (location_source="gps-live"); else manifest/injected
  ("manifest"); else None ("unavailable").
- static  -> surveyed manifest/injected coord is AUTHORITATIVE ("manifest"); do NOT
  consult gpsd even if serving (live jitter is noise for a fixed asset).
- unknown -> prefer manifest/injected; gpsd best-effort only if coords absent;
  never error.
- gpsd ABSENT is never an error — just "no live tier, use fixed tier." On static it
  is skipped on PURPOSE; on mobile only when absent/no-fix.

## Missing-value contract: wire sentinels normalize to Python None
The graceful-degradation rule for running against old/lagging core software:
never crash, never fake — resolve to None (mobility -> "unknown").
- **Wire sentinels** (for channels with no null, e.g. bare env vars):
  - VSN missing -> `0` (never a real VSN; real look like W09E/H00F)
  - lat/lon missing -> `999` (0 is a VALID coord = Null Island, so CANNOT be the
    sentinel; 999 is off-globe + greppable). 999 is the canonical literal; the
    normalizer also defensively rejects anything outside lat[-90,90]/lon[-180,180].
  - MOBILITY missing -> unset -> "unknown".
- **Normalize at the API boundary.** A field can arrive missing 3 ways: wire
  sentinel, genuinely absent, or a proper None (a newer correct WES). pywaggle2
  collapses ALL THREE to None. Sentinel-in and None-in are equivalent inputs; None
  is always the output. The plugin author NEVER sees 999 or 0 — preserves the
  "never fake an EXIF geotag" invariant (`if info.lat is not None:` else omit).
  Passing 999 through would be WORSE than Null Island (garbage that looks intended).

## WES-side contract (the CI-team "ask" — Infra #1)
WES injects per-pod env (and/or mounts node-manifest-v2.json):
| Env var | Real value | Sentinel |
|---|---|---|
| WAGGLE_NODE_VSN | W09E | 0 |
| WAGGLE_NODE_ID | 000048B0... | unset |
| WAGGLE_NODE_GPS_LAT | 41.8681 | 999 |
| WAGGLE_NODE_GPS_LON | -87.6134 | 999 |
| WAGGLE_NODE_MOBILITY | static\|mobile | unset (->unknown) |
- ALSO ask: add a top-level `mobility` field to node-manifest-v2.json (today it has
  none — node_type is form-factor not mobility; modem is backhaul not mobility;
  tags[] unused). Default `static` for current fleet.
- Confirm whether the CI team's forthcoming "GPS call" is itself a gpsd wrapper
  (§6.3) so pywaggle2 wraps the SAME source, not double-wraps.

## gpsd wire facts (verified live, W09E 2026-07-08)
- gpsd 3.17, JSON proto. Connect -> VERSION banner ->
  `?WATCH={"enable":true,"json":true};\n` -> TPV (lat/lon/alt/mode/time) + SKY
  (sats + hdop). mode: 0 unknown / 1 no-fix / 2 = 2D / 3 = 3D.
- Fix object should surface lat/lon/alt/fix_time/mode + optional hdop/n_sats_used
  merged from the adjacent SKY. A `read_averaged(n, timeout)` helper is reasonable
  (jitter smoothing) but optional for v1.
- gpsd host/port discovery: read `WAGGLE_GPS_SERVER` env (host:port) if set, else
  default to `wes-gps-server.default.svc.cluster.local:2947`.

## RESOLVED design decisions (DECIDED 2026-07-08, design §2.2.4)
All six earlier open points are now decided (Pete approved). Two changed from the
earlier leans — note them:
1. **lat/lon sentinel is the LITERAL `999`** (canonical value producers emit).
   Valid ranges are lat `[-90, 90]`, lon `[-180, 180]` (NOT `abs>90`/`abs>180` —
   that earlier phrasing was sloppy math; ±90/±180 are VALID). The normalizer
   treats `999`/`"999"`/`"999.0"` as missing -> None, AND defensively rejects any
   value parsing out of the valid range. But 999 is the documented sentinel.
2. VSN missing set = {`0`, `"0"`, `""`} all -> `vsn=None`. (accepted)
3. **`vsn_is_placeholder` is DROPPED.** NodeInfo exposes `location_source`
   (gps-live|manifest|unavailable) but NOT a placeholder flag: with vsn normalized
   to None when unresolved, `vsn is None` already means "unresolved" — a separate
   flag is redundant and invites drift. (image-sampler2's nodemeta.py still carries
   it only because it substitutes a visible "NODE" string; that behavior changes to
   None-when-missing on hoist.)
4. `get_vsn()` returns None when missing. (accepted)
5. Env vars are PRIMARY; mounted manifest is the fallback. (accepted)
6. gpsd via `WAGGLE_GPS_SERVER` env, default to the DNS name. (accepted)
The identity/GPS API shape is now LOCKED.
