# WES → pod config passing + node-manifest exposure safety

How WES delivers config into plugin pods today, and the design constraint for
exposing node identity/location to plugins. Companion to
`pywaggle2-nodeinfo-gps-design.md` (that ref = the pywaggle2 API shape; THIS ref =
the WES-side delivery channel + what is safe to expose). Settles the design
question: "env vars vs mount the manifest — and is the whole manifest safe?"

## Current WES→pod delivery model (verified via live pod + node inspection)
WES already uses BOTH channels, split by data shape — it is NOT "everything via env":
- **Env vars = a small handful of flat, pod-specific scalars.** A live `ses` pod
  (insect-bioclip, H00F) has only: `WAGGLE_PLUGIN_HOST/PORT/USERNAME/PASSWORD`,
  `WAGGLE_APP_ID`, `WAGGLE_SCOREBOARD`. Runtime wiring, nothing structured.
- **Filesystem mounts = the structured/shared config.** Pods mount
  `/run/waggle/data-config.json` (camera/sensor config, a JSON doc) and
  `/run/waggle/uploads` (spool dir). WES has ALREADY made the architectural choice
  that structured config is a curated FILE, not a pile of env vars.
- `/etc/waggle/node-manifest-v2.json` (+ `/etc/waggle/vsn`, `/etc/waggle/node-id`)
  is a node-HOST path, NOT mounted into pods — the reason plugins can't self-identify.

Design implication: this is NOT a greenfield env-vs-file choice. The manifest
belongs on the file side of a line WES already drew. Recommended ask to CI = BOTH,
mapping onto their own precedent:
1. Env for the ~5 hot scalars (vsn, node_id, lat, lon, mobility) — inherently a
   whitelist (CI picks each var), safe by construction, zero-parse for bash/non-Python.
2. A curated node-info FILE mounted in-pod (e.g. `/run/waggle/node-info.json`) —
   the primary, extensible, single-source channel, mirroring how data-config.json
   is already published.
3. Live GPS (mobile nodes) stays a SEPARATE runtime call (Tier-2 gpsd wrapper) —
   neither env nor a static file can carry a moving fix.
The pywaggle2 resolver already does per-field precedence (explicit > runtime > env
> mounted file), so supporting all channels costs the library nothing — tell CI
"provide whichever you can, we read what's present." Most adoptable ask.

## CRITICAL: do NOT mount the raw manifest — it over-shares
"Mount the manifest" wrongly assumes the whole file is safe for arbitrary 3rd-party
plugin code. It is not. Field-by-field audit of a real `node-manifest-v2.json`
(H00F, keys: address computes gps_lat gps_lon lorawanconnections modem name phase
project resources sensors tags vsn):

SAFE / intended (the identity surface we actually want):
- `vsn`, `name` (node_id), `gps_lat`, `gps_lon`, `tags`, `phase`, `project`.

QUESTIONABLE (probably withhold; more than a plugin needs):
- `address` — human street address ("Argonne\r\n9700 South Cass Ave..."). gps_lat/lon
  already give location; postal address is PII-adjacent and sensitive for private/
  restricted sites.
- `computes[].serial_no` / `sensors[].serial_no` — hardware serials = asset/inventory
  data; no plugin business.

SENSITIVE — MUST withhold:
- `sensors[].uri` — internal endpoints. On H00F: `http://<internal-IP>/stw-cgi/...`.
  Leaks (1) internal network topology (private IPs of every device) and (2) on nodes
  still using the credentialed-URI anti-pattern (`rtsp://user:pass@host`, Infra #10)
  it leaks CAMERA CREDENTIALS to every plugin — directly contradicts pywaggle2 §3.2
  (creds from secret, never exposed).
- `modem` — null on H00F but schema holds cellular config (APN, SIM/IMEI, carrier
  acct) on cellular-backhaul nodes.
- `lorawanconnections` — empty on H00F but schema holds LoRaWAN join creds
  (DevEUI/AppEUI/AppKey/PSK) = cryptographic keys. Never plugin-readable.

Note: H00F happens to have modem=null and lorawanconnections=[], so their
sensitivity is reasoned from the SCHEMA, not populated values — inspect a
cellular/LoRaWAN node to make the "withhold" argument airtight.

## VERIFIED on a populated LoRaWAN node (W096, 2026-07-09)
Ran the probe on W096 (old-style login, LoRaWAN). Findings that CORRECT/sharpen the above:
- `lorawanconnections` had 9 entries. Each carries `lorawandevice.deveui` (16-hex
  DevEUI device id) + per-device cross-tenant telemetry: `last_seen_at`, `margin`
  (RF link margin), `battery_level`, `expected_uplink_interval_sec`, `created_at`.
- **CORRECTION:** the manifest stores DevEUIs but NOT the OTAA join secrets —
  AppKey/NwkKey/AppEUI live in the LoRaWAN network server, NOT in the manifest. So
  raw-manifest exposure is NOT a crypto-key leak (earlier "holds AppKey/PSK" was a
  schema over-guess); it IS still device-identity/inventory + cross-tenant telemetry
  a plugin has no need for. Still withhold `lorawanconnections` (at most a count/flag).
- `deveui` is the KILLER example for whitelist-not-blacklist: its name has no
  key/secret/password token, so a naive "strip anything that looks secret" blacklist
  passes it straight through. Only an explicit allow-list is safe.
- W096 `sensors[].uri` were empty (LoRaWAN sensors have no HTTP uri), but H00F's
  camera `uri` = internal IP endpoint stands. `address` = "1020 S Union Ave,
  Chicago..." confirms precise street address exposure. `modem` null on W096 too
  (still unseen populated — treat sensitive-by-default).

## VERIFIED WES source architecture (waggle-edge-stack + edge-scheduler, 2026-07-09)
The delivery mechanism, from reading the actual source (not just live pods):
- **Env identity today = `wes-identity` ConfigMap**, generated by
  `waggle-edge-stack/kubernetes/update-stack.sh::update_wes()` writing
  `configs/wes-identity.env` — currently ONLY `WAGGLE_NODE_VSN` + `WAGGLE_NODE_ID`
  (from `/etc/waggle/{vsn,node-id}`). Kustomize `configMapGenerator` turns it into
  the CM; WES SYSTEM pods consume via `envFrom: configMapRef: wes-identity`.
- **data-config.json** ConfigMap `waggle-data-config` is made by
  `update_data_config()` (`kubectl create configmap ... --from-file`) and
  subPath-mounted at `/run/waggle/data-config.json`. This is the exact pattern to
  MIRROR for a curated node-info.json.
- **Raw manifest** synced from `auth.sagecontinuum.org/manifests/<vsn>/` to
  `/etc/waggle/`, hostPath-mounted only into privileged SYSTEM pods
  (device-labeler, camera-provisioner, chirpstack-tracker) — never plugin pods.
- **THE PLUGIN POD SPEC IS BUILT BY edge-scheduler, NOT the YAMLs.** File:
  `edge-scheduler/pkg/nodescheduler/resourcemanager.go`, pod-template builder
  (~L589 env, ~L677 volumes, ~L718 volumeMounts). `wes-dev-notebook.yaml` is a
  hand-written mirror of what it emits. Any change reaching ALL plugins must go here.
- **KEY FIND — GPS wiring already exists:** the builder already injects
  `WAGGLE_GPS_SERVER=wes-gps-server.default.svc.cluster.local` and `HOST`
  (fieldRef spec.nodeName) into every plugin pod. So pywaggle2 Tier-2 `GPS()` needs
  NO WES change. Gap = NO `WAGGLE_NODE_VSN/ID`, no gps/mobility, no `envFrom
  wes-identity` on plugin pods.

## Concrete two-repo diff (the reviewable CI ask)
1. **edge-scheduler `resourcemanager.go`:** add `EnvFrom` referencing `wes-identity`
   (Optional=true) to the plugin container; add a `waggle-node-info` volume +
   subPath mount at `/run/waggle/node-info.json` (structurally identical to the
   existing `waggle-data-config` entries, Optional).
2. **waggle-edge-stack `update-stack.sh`:** append `WAGGLE_NODE_GPS_LAT/LON` +
   `WAGGLE_NODE_MOBILITY` (via jq from manifest) to `wes-identity.env`; add
   `update_node_info()` (mirror of `update_data_config()`) that jq-whitelists
   `node-info.json` from the manifest and `kubectl create configmap waggle-node-info`.
Both are additive, reuse existing mechanisms, no new privileged access, no raw
manifest exposure. Full writeup: `~/AI-projects/pywaggle2-design.md` §2.4.

## The design rule
WES must expose a plugin-facing node-info VIEW that is a WHITELISTED subset of the
manifest — never the raw file. Whitelist not blacklist, so a new sensitive field
added upstream later doesn't silently leak by default. Suggested view: vsn, node_id,
gps_lat, gps_lon, mobility, tags, phase, project + a SANITIZED sensors list
(name/scope/hardware-model/capabilities only; strip `uri` and `serial_no`). Raw
manifest stays host-only. This reframes the CI ask from "mount your manifest"
(a reviewer should reject) to "publish a curated node-info projection" (same thing
they already do for data-config.json). The whitelist itself should be a documented,
reviewable contract, not hardcoded.

## Prototyping a WES change for the CI team (build+test recipe, 2026-07-09)
When asked to actually BUILD/TEST a platform change (not just design it), make a
standalone repo OUTSIDE the frozen brain (`~/AI-projects/<name>/`) that produces
APPLYABLE PATCHES + a real test harness. Pattern that worked
(`~/AI-projects/wes-nodeinfo-injection/`, the node-identity-env change):
- **Shallow-clone the real upstreams** into `.upstream/` (gitignored):
  `git clone --depth 1` waggle-edge-stack + edge-scheduler. Note the pinned dep
  version from `edge-scheduler/go.mod` (`k8s.io/api v0.23.1`) and MATCH it in any
  isolated Go harness so the k8s types are identical.
- **Extract the changed logic into a standalone testable unit** rather than testing
  the whole giant program. The bash `wes-identity.env` generation → a tiny
  `gen-*.sh` that mirrors upstream's `node_id()/node_vsn()` helpers + adds the jq
  lines. The Go container-build change → a small module reproducing just the
  `apiv1.Container{...}` literal + the added `EnvFrom`.
- **Fixtures from REAL nodes** (H00F camera + W096 lorawan): include the SENSITIVE
  fields verbatim so no-leak assertions are meaningful (grep the generated env for
  `deveui`, sensor `uri`, `serial_no`, street address → must be ABSENT). Add
  minimal/mobile/nomanifest variants to exercise every sentinel path.
- **Sentinel design (matches pywaggle2 §2.2.3):** VSN missing→`0`; node_id→empty;
  lat/lon→`999` (off-globe; 0 is Null Island = a REAL coord, so range-detect
  |lat|>90/|lon|>180 not a literal); mobility missing→empty→reader yields `"unknown"`.
  Reader normalizes ALL of {sentinel, missing, proper-null} → Python None so the
  plugin author never sees 0/999 (preserves never-fake-EXIF-geotag invariant).
- **Verify against the REAL upstream, not just the mock:** `go build ./pkg/nodescheduler/`
  + `go test ./pkg/nodescheduler/` on the patched `.upstream/edge-scheduler` proves
  the change compiles in-situ and doesn't regress upstream tests — strongest evidence.
- **Generate real unified-diff patches** (diff orig vs patched, sed the paths to
  `a/`…`b/…` upstream-relative) and gate them with `git apply --check` against a
  pristine `git archive HEAD` extract → "applies CLEAN". Ship `patches/` as the
  deliverable; `.upstream/` is just for local build/test.
- **k8s EnvFrom precedence to rely on:** `container.Env` overrides `EnvFrom`, so an
  explicit env var still wins over the ConfigMap — layer identity CM UNDER Env, use
  `Optional: true` so a node whose WES hasn't made the CM yet still schedules (safe
  rollout / DRY-run friendly).
- Go not preinstalled on aarch64 DGX: fetch the official arm64 tarball to
  `/usr/local/go` (apt's is stale); export `GOPATH`/`GOCACHE` under $HOME.
- Ship a `Makefile` with a canonical `test` target (so verification hooks detect it)
  running all layers, plus `patches-check` + `test-upstream`; README + HANDOFF that
  separate DONE from CI-owned (e.g. add `mobility` manifest field is the one true
  schema ask; the curated node-info.json file channel is phase-2, env scalars suffice).

## Probe recipe (run to ground when finalizing the design)
- Dump manifest keys + value TYPES (redacted): `sudo python3` reading
  `/etc/waggle/node-manifest-v2.json` on `USER@node-<VSN>.sage`. Pipe the script
  via stdin (`ssh ... 'sudo python3' < probe.py`) — heredoc f-strings collide with
  bash quoting; a stdin'd file avoids it.
- To prove sensitivity: inspect a node with a populated `modem` / `lorawanconnections`.
- Source of truth for the field set + per-project variation = the manifest schema in
  WES/beehive source (read alongside the data-config.json generation template — that
  template is the pattern to mirror for a node-info projection).
