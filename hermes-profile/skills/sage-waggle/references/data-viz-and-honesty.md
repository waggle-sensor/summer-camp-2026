# Sage data visualization & data-honesty rules

Hard-won from building a 3D web globe over Sage fleet data. Two things matter most:
(1) NEVER fabricate scientific data, and (2) discover real measurement names before
you theme around them.

## RULE 1 — Never synthesize sensor values (data honesty)

A viz/tool over scientific sensor data must show ONLY real readings. Do not fill
gaps with synthetic/placeholder/"demo" values, even clearly-labeled ones.

- Why: a precise-looking fake number (e.g. "PM2.5 = 6.9 µg/m³" on a node with no
  air-quality sensor) reads as real and misleads, even with a "demo" label. Pete
  caught exactly this and rejected the whole demo-fallback approach.
- Correct behavior: a node that doesn't publish a measurement renders NOTHING for
  that layer; the detail panel shows "— no reading". Uneven/sparse coverage is the
  truth of the fleet, not a bug to paper over.
- Consequence to accept: with real-data-only, the tool needs a live connection to
  show anything (see CORS below). An empty view with "run the server" guidance beats
  a full view of lies. Offer a timestamped real snapshot ("as of <ts>") if an
  offline view is wanted — never a generated one.
- General principle: applies to any scientific-data tool, not just Sage.

## RULE 2 — Discover REAL measurement names before theming

Do NOT guess measurement names. Many plausible names (aqt.particulate_matter.pm2.5,
env.gas, env.detection.avian, env.count.car) return ZERO rows — they don't exist or
aren't flowing. Probe the live API first.

Discover what actually flows (last 30m, distinct names + counts):
```bash
curl -s -X POST https://data.sagecontinuum.org/api/v1/query \
  -H "Content-Type: application/json" -d '{"start":"-30m","tail":1}' \
  | grep -o '"name":"[^"]*"' | sort | uniq -c | sort -rn | head -60
```

Per-measurement node coverage (how many distinct nodes report it):
```bash
curl -s -X POST https://data.sagecontinuum.org/api/v1/query \
  -H "Content-Type: application/json" \
  -d '{"start":"-1h","filter":{"name":"env.temperature"},"tail":1}' \
  | grep -o '"vsn":"[^"]*"' | sort -u | wc -l
```

### Fleet reality (verified 2026-07, ~289 nodes, ~180 deployed)
Coverage is dominated by SYSTEM telemetry, then environment, then sparse plugins:
- sys.* (thermal, power, uptime, cpu, mem, net): ~108–130 nodes — BEST coverage.
- env.temperature / env.relative_humidity / env.pressure (BME680): ~60 nodes.
- upload (camera images to object store): ~46 nodes; value is the image URL.
- aqt.gas.no2: ~8 nodes.  iio.in_resistance_input (VOC proxy): ~23 nodes.
- Particulate PM2.5/PM10, bird/vehicle/person counts, cloud/rain: NOT flowing
  fleet-wide (plugin-specific, intermittent, or wrong name). Don't theme on them.
Theme your viz around what's actually there. Good themes: Weather, Node Health,
Camera Network, Air Quality (mark it sparse).

## API essentials (public, no auth for reads)

- Endpoint: `POST https://data.sagecontinuum.org/api/v1/query`, body JSON, returns
  NDJSON (one JSON object per line). `tail:N` = latest N per stream.
- Time window: `{"start":"-3h"}` for recent; `{"start":"-720h","end":"-696h"}` for a
  past 24h window (works — good for a historical time slider).
- Each row: `{timestamp, name, value, meta:{vsn, node, sensor, plugin, ...}}`. Join
  to node geometry by `meta.vsn`.
- SENTINEL: bme680-not-present reports `value:-130.11`. Filter it (v>-120). Always
  add a per-layer `valid(v)` guard to drop sentinels/garbage.

## CORS: browser fetch is blocked from file:// (and most origins)

Direct browser `fetch()` to data.sagecontinuum.org fails CORS ("origin 'null'" on
file://). Two fixes:
- Ship a tiny stdlib http server that serves the page AND proxies the API, injecting
  `Access-Control-Allow-Origin: *`. See templates/sage-cors-proxy-server.py.
- Point the page's API base at the proxy when a `?proxy=1` flag is present, else the
  public API (for allowed-origin hosting).

## Self-contained 3D globe build notes (three.js)

- Single HTML, three.js via CDN. Bake data as compact JS arrays (NODES as
  `[vsn,lat,lon,region,cls]`).
- Node coords: geocode the human-readable deployment location strings from
  `list_all_nodes` with a small hand-built gazetteer; jitter co-located nodes
  deterministically (hash VSN) so stacks don't overlap. These are APPROXIMATE — say so.
- Base map on the sphere: fetch Natural Earth 110m land + admin-1 GeoJSON, decimate
  hard (drop points closer than ~1.5° world / ~0.8° US; round to 1 decimal) → ~38 KB
  of flat `[lon,lat,...]` rings, draw as THREE.LineSegments with the SAME lat/lon→
  sphere projection as the markers so continents line up under the bars. Without a
  map the features float over a bare sphere and you can't tell where nodes are.
- WebGL guard: wrap `new THREE.WebGLRenderer()` in try/catch; on failure show a
  "needs WebGL" message and stub the renderer so panels/legend still build. Without
  this the whole app dies on machines with no WebGL.

## Verification without a GPU (headless WebGL often unavailable, esp. aarch64)

Headless Chromium on aarch64 has NO working WebGL (no Chrome-for-Testing ARM64;
swiftshader won't init) — you can verify logic but NOT rendered pixels. What you CAN do:
- puppeteer-core + system chromium: load page, capture pageerror/console.error, probe
  DOM state (panels built? theme switch updates legend?). DOM reflects that JS ran.
- Data/geometry checks in plain Node: parse baked arrays from the HTML, confirm all
  coastline points project onto the sphere (radius≈1.0), and that known landmarks
  (London/Sydney) land near their coastline — proves map & nodes share one projection.
- Test the CORS proxy server-side with curl (real data + CORS header) — fully
  verifiable without a browser.
- Be honest in the summary: "verified logic/data/UI; could not render 3D pixels here."
