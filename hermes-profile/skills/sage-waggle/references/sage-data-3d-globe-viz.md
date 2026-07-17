# Building a self-contained 3D web viz of Sage node data

A reusable recipe for a single-file `sage-globe.html` (three.js via CDN, no build
step) that shows the fleet's data on an interactive 3D globe, grouped into coherent
themes. Hand it to students/testers — they just open it. Proven on the Sage fleet
(166 geocoded deployed nodes across 38 regions).

## Data foundation

**Node geometry (baked in).** Get the roster from the Sage MCP
(`mcp_sage_list_all_nodes`) — it returns `VSN (MAC): <human location string>` for
~180 deployed nodes. There are NO exact survey lat/lons in it, so geocode the
human location strings with a small hand-built gazetteer (substring → lat/lon/region;
first match wins, order by specificity — "Cuyamaca Peak" before "CA"). Jitter
co-located nodes deterministically (hash the VSN → small lat/lon offset) so stacks
at one site (e.g. dozens at Argonne/Lemont) don't perfectly overlap. Emit a compact
JS array `[[vsn,lat,lon,region,cls],...]` (~8KB for 166 nodes). Be explicit in the
README that coordinates are geocoded-approximate, not survey-grade.

**Live values (public API, no auth for reads).**
`POST https://data.sagecontinuum.org/api/v1/query`, body e.g.
`{"start":"-6h","filter":{"name":"env.temperature"},"tail":1}`. Response is NDJSON,
one JSON object per line, each with `value` and `meta.vsn` (join key to node geom).
- **Sentinel filtering:** the BME680 emits `-130.11` when the sensor is absent —
  drop values `<= -120` (and absurd highs) or the map lights up with fake cold.
- **Images / object store:** query `{"filter":{"name":"upload","vsn":"<VSN>"}}` →
  `value` is a real `https://storage.sagecontinuum.org/.../<file>.jpg` URL. Use it to
  deep-link (or best-effort inline) a node's recent camera frames.

## The CORS reality (design-forcing)

Browsers block `file://` (origin `null`) → `data.sagecontinuum.org` with a CORS
preflight failure. So a student who double-clicks the HTML will NOT get live data.
Two-part solution that keeps the file self-contained AND useful:
1. **Seeded synthetic fallback** baked into the file: deterministic, region-flavored
   values (fire country hotter/drier, cities more traffic, preserves more birds) so
   the globe is always explorable. A status pill must clearly say **● live** vs
   **○ demo** so nobody mistakes synthetic for real.
2. **A tiny stdlib CORS-proxy launcher** (`sage-globe-serve.py`): a
   `http.server` that serves the page over http AND forwards `POST /sage-proxy` to
   the Sage API, adding `Access-Control-Allow-Origin: *` on the way back. The HTML
   checks `?proxy=1` and points fetches at `/sage-proxy` instead of the direct API.
   `python3 sage-globe-serve.py` → real data. No dependencies.

## Rendering essentials (three.js)

- **WebGL fallback (do NOT skip):** wrap `new THREE.WebGLRenderer()` in try/catch.
  If it throws (old GPU, locked-down lab, some remote desktops), the WHOLE app dies
  at line 1 of scene setup — panels, legend, everything — unless you catch it and
  (a) show a friendly "needs WebGL" message and (b) stub the renderer
  (`{domElement, render(){}, setSize(){}, setPixelRatio(){}}`) so the rest of the
  script (panel builders, live fetch) still runs. This was a real bug found by test.
- **The map on the sphere (else nodes float with no context):** a bare colored
  sphere gives no geography. Draw coastlines + (for a US-heavy fleet) state borders
  as `THREE.LineSegments` from decimated Natural Earth 110m vectors, embedded in the
  file (offline-safe, ~38KB). Fetch `ne_110m_land.json` + `ne_110m_admin_1_states`
  from the martynafford/natural-earth-geojson repo, decimate (drop points closer
  than ~1.5°, round coords to 1 decimal), emit flat `[lon,lat,...]` rings. CRITICAL:
  draw them with the SAME `ll2v(lat,lon)` projection the node markers use, at a
  slightly larger radius (R*1.005) — then continents line up exactly under the bars.
- Node values → color (palette lerp) + bar height (extrude along surface normal).

## Coherent themes, not one heap

Do NOT dump every measurement into one list. Group into themes, each a small set of
related layers with a coherent palette. Proven grouping:
- 🌦️ Weather (temperature, humidity, pressure)
- 🌫️ Air Quality (PM2.5, PM10, gas/VOC)
- 🔥 Wildfire (heat, smoke=PM2.5, dryness=inverted humidity) — many Sage nodes sit
  on real CA/OR fire-country peaks (Palomar, Cuyamaca, Selma)
- 🐦 Ecology (BirdNET detections, cloud cover, rain)
- 🏙️ Urban Pulse (vehicle/person counts, sound level)
Some measurement names vary by plugin (object counts, acoustic SPL, avian
detections) — make the `THEMES` object the single knob and note in the README that
those `meas:` strings may need adjusting for a specific class's plugins.

Controls that work well: theme selector, per-theme layer radio, 3-month time slider
+ animate, value threshold (hide low), view presets (Globe/USA/Chicago/fire),
auto-rotate, bars-vs-dots, click-node detail panel with object-store image link.

## Verification limits (aarch64 / headless)

This host has NO headless WebGL (no Chrome-for-Testing ARM64 build; swiftshader
fails to create a GL context). So you can verify, WITHOUT a GPU:
- HTML/JS runs error-free + UI builds — headless Chromium via puppeteer-core, probe
  DOM state (`.theme` count, legend text, theme-switch), collect `pageerror`. NOTE:
  top-level `const`/`let` are NOT on `window`; probe via DOM, not the variable names.
- Map geometry consistency — a plain Node script: parse COAST/USB/NODES out of the
  HTML, run `ll2v` on them, assert all coastline points land on the unit sphere and
  that known cities (London/Sydney) sit near coastline points and US nodes near
  borders. This proves continents align with nodes without rendering pixels.
- The CORS proxy — start `sage-globe-serve.py`, `curl` `/sage-proxy` for real
  temperature + an `upload` image URL, confirm `Access-Control-Allow-Origin` header.
You CANNOT verify the rendered 3D visually here — say so honestly and ask the owner
to eyeball it on a GPU machine before sharing. Do not claim the visual is confirmed.
