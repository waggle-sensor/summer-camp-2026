# Node identity sourcing + pywaggle upload contract (VERIFIED)

Verified 2026-07 against pywaggle source + a live H00F pod. These are durable
platform facts a plugin author needs to get provenance and uploads right.

## Node identity is NOT in pod environment variables

A common wrong assumption is that the scheduler injects `WAGGLE_NODE_VSN`,
`WAGGLE_NODE_LAT`, `WAGGLE_NODE_LON`, etc. **They do not exist.** pywaggle reads
ONLY messaging-plumbing env vars:

    WAGGLE_PLUGIN_USERNAME / _PASSWORD / _HOST / _PORT
    WAGGLE_APP_ID
    WAGGLE_PLUGIN_UPLOAD_PATH   (default /run/waggle/uploads)
    PYWAGGLE_LOG_DIR

The only node-ish env var in a pod is `KUBENODE=<hwid>.<compute>` (hardware id,
NOT the VSN).

### /etc/waggle/ files EXIST ONLY ON THE NODE HOST — NOT inside pods

    /etc/waggle/node-manifest-v2.json   # {"vsn","name"(=node_id),"gps_lat","gps_lon","project",...}
    /etc/waggle/vsn                      # e.g. "H00F"
    /etc/waggle/node-id                  # e.g. "00004CBB4701D16C"

CRITICAL CORRECTION (verified by a real pod round-trip on H00F): these files are
on the node HOST filesystem. They are NOT mounted into plugin pods. A real
scheduler-launched pod (`ses` namespace) mounts ONLY `/run/waggle/uploads` and
`/run/waggle/data-config.json`, and its env has only `WAGGLE_PLUGIN_*` /
`WAGGLE_SCOREBOARD`. `data-config.json` is camera-stream routing only — no vsn,
no GPS anywhere in the pod.

=> DO NOT design a plugin to REQUIRE reading the manifest for vsn/lat/lon. Reading
`/etc/waggle/*` succeeds when you run the code directly on the node host
(`ssh node; python app.py`) — which makes host-side tests PASS MISLEADINGLY — but
FAILS in the actual pod with "node VSN could not be resolved". ALWAYS verify
identity logic in a real pod (`pluginctl run`), not just a host run.

### How identity actually gets attached (the correct model)

Beehive stamps node identity DOWNSTREAM via message routing (the RabbitMQ scope /
`WAGGLE_APP_ID`). The existing yolo/bioclip plugins do NOT handle vsn/lat/lon at
all — they just call `plugin.upload_file(...)` and let the platform attribute the
node. Follow that model:
  - Treat vsn/lat/lon as OPTIONAL enrichment passed via flag/env, never a hard
    requirement. Never block an upload because vsn is unresolved.
  - Do NOT put vsn in a filename the plugin must generate unaided inside a pod.
  - If you want a downloaded bare object to be self-describing, embed whatever
    identity you WERE given (flag/env) into EXIF/meta, and omit it otherwise.
  - If a plugin genuinely needs the manifest in-pod, you must explicitly mount it
    (`-v /etc/waggle:/etc/waggle`) — but real SES jobs don't, so relying on it is
    not fleet-portable.

CONFIRMED BY FULL BEEHIVE ROUND-TRIP (image-sampler2 on H00F, July 2026): an
upload whose filename used a PLACEHOLDER vsn "NODE" came back from the data API
with `meta.vsn=H00F, meta.node=00004cbb4701d16c`. Downstream attribution is
correct regardless of what the plugin knows — proving the model above.

### Interim placeholder pattern (until runtime GPS/VSN calls ship)

When identity is unresolved but you still want the file self-described:
  - vsn -> clearly-marked PLACEHOLDER (e.g. "NODE", env-overridable), flagged +
    WARNING logged, NEVER fatal.
  - lat/lon -> OMIT from EXIF; never fabricate coordinates (fake geo corrupts data).
Keep the runtime lookup behind ONE grep-able swap-in point (tag `TODO(sage-ci)`)
so it's a one-function change when the CI team's runtime "GPS call" + "VSN call"
land. Reference impl: image-sampler2 `nodemeta.py::_runtime_identity()`. See also
`references/node-gps-location-resolution.md` and
`~/AI-projects/Infra-problems-to-fix.md` (issue #1).

### NodeInfo mobility (poll-once vs poll-periodically) → see node-gps-location-resolution.md

When designing the runtime node-info accessor, INCLUDE a `mobility` tri-state
(`"static" | "mobile" | "unknown"`) so a plugin knows whether re-polling location
is ever worthwhile: static → resolve once at startup; mobile → may re-poll on a
science-driven cadence; unknown drives conservative behavior. Bake "resolve once
on static" into the library via `get_node_info(max_age=…)`. NB the manifest has NO
mobility signal today — `node_type`/`modem`/`gps` are all red herrings; it must be
added as an explicit field. Full design + fleet-survey evidence + the caching
contract live in `references/node-gps-location-resolution.md` ("NodeInfo design
refinements" + "The manifest has NO mobility signal today") and
`~/AI-projects/pywaggle2-design.md` §2.2/§2.3. Don't duplicate it here.

## pywaggle upload contract (from uploader.py source)

`Plugin.upload_file(path, meta={}, timestamp=None, keep=False)`:

- `timestamp = timestamp or get_timestamp()` — passing `timestamp=capture_ts_ns`
  SHORT-CIRCUITS the default, so the RECORD/object is keyed by CAPTURE time. This
  is the one-line "capture-time naming" switch. Storage dir = `root/<timestamp>-<sha1sum>/`
  containing `data` + `meta`.
- The staged `meta` file is `{"timestamp":<int>, "shasum":<sha1>, "labels":{...}}`
  and pywaggle injects `labels["filename"]` = the path basename.
- **`valid_meta` requires ALL meta values to be strings.** Stringify every label
  (ints like capture_ts_ns -> str) or the publish/upload fails.
- pywaggle's object checksum is **SHA1** (upload dir name); unrelated to any
  SHA256 you embed for your own provenance.
- pywaggle does NOT add node vsn/lat/lon to the upload — add them yourself as
  string labels if you want them in the record, and/or embed in the file.

## Verifying uploads without Beehive (local staging contract)

Point `WAGGLE_PLUGIN_UPLOAD_PATH` at a temp dir and run the plugin: pywaggle
stages `<capture_ts>-<sha1>/{data,meta}` there — exactly what the on-node upload
agent later ships to Beehive. Inspect the `meta` JSON (timestamp==capture ts, all
label values strings) and the `data` bytes. This proves the upload contract with
no cloud dependency; a full Beehive round-trip (real pod + WAN) is a separate,
heavier check.
