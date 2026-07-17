# Building a self-contained web viz of Sage data

Reusable recipe for a shareable HTML/JS visualization of fleet-wide Sage data
(built for a "3D globe of last 3 months, all nodes, themed" ask; the technique
generalizes to any map/dashboard).

## Key decisions that worked

- **Single self-contained `.html`** (three.js via CDN `unpkg.com/three@0.160.0`,
  no build step). Students/friends just open it. Bake the node geometry INTO the
  file as a compact JS array `[[vsn,lat,lon,region,cls],...]` so it works offline.
- **Themes, not a heap.** Group the (huge) measurement list into a few coherent
  themes, each with a palette + a handful of layers. What we shipped:
  Weather (temp/humidity/pressure), Air Quality (pm2.5/pm10/gas),
  Wildfire (heat/smoke=pm2.5/dryness=inverted RH), Ecology (BirdNET/cloud/rain),
  Urban Pulse (vehicles/people/sound). Put the theme model in one `THEMES` object
  at the top of the script so it's the single knob to customize.
- **Node geocoding.** The node roster gives human location strings, not coords.
  Build a substring gazetteer (place-key -> lat/lon/region), match most-specific
  first, and deterministically jitter co-located nodes (hash the VSN) so stacks at
  e.g. Argonne/Lemont don't perfectly overlap. ~166/166 deployed nodes geocoded
  this way across ~38 regions. Label them APPROXIMATE — they're from location
  strings, not survey coords.

## Live data: the public API + the CORS wall

- Public query API (NO auth for reads): `POST https://data.sagecontinuum.org/api/v1/query`
  body `{"start":"-15m","filter":{"name":"env.temperature","sensor":"bme680"},"tail":2}`,
  returns **NDJSON** (one JSON object per line). `meta.vsn` is present -> join to
  node geo. Value `-130.11` is the bme680-not-present sentinel — filter it out
  (`v>-120`).
- **Browsers block `file://` -> API over CORS** (`origin 'null'` ... "No
  'Access-Control-Allow-Origin' header"). Confirmed real. So a file opened directly
  will almost always fall back to demo data.
- **Fix = ship a tiny stdlib proxy** (`sage-globe-serve.py`): `http.server` that
  serves the page AND proxies `POST /sage-proxy` -> the Sage API, adding
  `Access-Control-Allow-Origin: *` on the way back. Page detects `?proxy=1` and
  targets `/sage-proxy` instead of the direct API. Verified end-to-end: real
  temps + a real object-store image URL flow through with the CORS header.

## Always-works fallback (do this)

- **Seeded synthetic data** when live is unreachable, clearly flagged in the UI
  (status pill: `● live` vs `○ demo`). Make it deterministic + region-flavored
  (fire country hotter/drier, cities busier, preserves more birds) so themes are
  legible — but never let it masquerade as real.
- **WebGL guard (real bug we hit):** `new THREE.WebGLRenderer()` THROWS on machines
  without WebGL, which kills the whole script (panels never build). Wrap it in
  try/catch, show a "needs WebGL" message, and stub the renderer
  (`{domElement:canvas,render(){},setSize(){},setPixelRatio(){}}`) so the rest of
  the app (panels, legend, data) still runs.

## Object-store image links

- Camera frames live in the object store; `filter:{name:"upload",vsn:VSN}` returns
  records whose `value` is the image URL
  (`storage.sagecontinuum.org/api/v1/data/.../*.jpg`). Per-node detail panel can
  deep-link to `portal.sagecontinuum.org/data?nodes=VSN` and best-effort inline the
  latest frame. Protected nodes need auth (`curl -L -u user:token`), so treat
  inline images as best-effort.

## Verification on a headless/aarch64 box (blocker to know)

- Headless WebGL does NOT work on aarch64 here (no Chrome-for-Testing ARM64 build;
  swiftshader won't init). You CAN verify: JS runs error-free + all UI builds via
  a puppeteer-core DOM probe (query `.theme`/`#layers` counts, click a theme, read
  `#legtitle`); the proxy live-data path via `curl`; `python3 -m py_compile` the
  server. You CANNOT capture the rendered 3D pixels — say so honestly and ask the
  user to eyeball it on a GPU machine. NOTE: `const`/`let` top-level vars are NOT
  on `window`, so probe via DOM/behavior, not `page.evaluate(()=>NODES)`.
