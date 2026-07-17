# pywaggle2 features + the producer/consumer cache pattern (class-level)

How the new Sage/Waggle scaffolding fits together, and how to build a **cache
consumer plugin** on top of it. Grounded in the shipped repos (2026-07), reusable for
any future consumer (sage-yolo2, bioclip2, etc.), not one plugin.

## "pywaggle2" = an umbrella name for THREE tightly-linked pieces

pywaggle2 is NOT one repo. It is the collective set of new features that let a plugin
know where it is and hand data to neighbors. Three pieces = one capability:

| Piece | Repo | Role |
|---|---|---|
| Node-info INJECTION (WES) | `wes-nodeinfo-injection` | scheduler puts VSN/node_id/GPS/mobility into every pod's env as `WAGGLE_NODE_*` (5 vars). Two patches: update-stack.sh ConfigMap + edge-scheduler EnvFrom. |
| Node-info READER (library) | `pywaggle2-nodeinfo` | plugin-side `read_node_info() -> NodeInfo(vsn, node_id, lat, lon, mobility, vsn_is_placeholder)`; sentinel→None/"unknown", never fabricate a coord. |
| Cache MANAGER (WES) | `wes-local-cache-manager` | bounds shared `/local-cache` (per-unit + per-node byte caps, oldest-first sweep). Layer-2 blunt quota; plugins own Layer-1 graceful eviction. |

These THREE **enable** `image-sampler2` (the first plugin built on them: produces
frames to `/local-cache`, geotags via node-info; upload is a TEST path, not its job).

What pywaggle2 does NOT yet implement (design-only, in sage-design-planning/
pywaggle2-design.md §1/§3): the Layer-1 cache PRIMITIVE (`cache_file`/`read_cache` —
currently lives only as `image-sampler2/cache.py`, not hoisted into a library), the
live-GPS Tier-2 gpsd wrapper, and the still-first/EXIF-preservation acquisition
ladder. When asked "what else is in pywaggle2 code" the honest answer is: node-info
out + node-info in + cache quota manager — nothing more.

## The self-describing cached frame (the consumer's contract)

image-sampler2 writes frames a consumer reads. Verified format (cache.py/metadata.py):
- **Per-stream dir:** `<cache-root>/<cache-name>/<camera>/`. Root default `/local-cache`.
- **Filename:** `<capture_ts_ns>-v2-<vsn>-<camera>.jpg`. capture_ts_ns (all-digits
  prefix, anchored on the `-v2-` marker) is the AUTHORITATIVE ordering key — NOT mtime.
- **In-flight writes:** `*.tmp` then atomic rename. Consumers ignore `*.tmp`; only
  committed `-v2-` files are members. (scan_ring / parse_v2_name.)
- **EXIF + UserComment JSON** (maximum metadata): DateTimeOriginal, Make (camera/
  acquisition path), Model (vsn), Software (plugin+ver), ImageUniqueID (SHA256 of
  ORIGINAL frame bytes), GPS tags; JSON blob = schema_version, vsn, node_id, job,
  task, plugin, camera, capture_timestamp_ns, upload_timestamp_ns, unique_id,
  object_name, lat, lon, acquisition_path.

**Consumer output should be FRAME-ANCHORED:** observation_ts = frame capture_ts (NOT
now()); echo unique_id for provenance; attribute with the FRAME's captured identity
(cross-check vs the pod's own get_node_info(), warn on mismatch); carry
acquisition_path as a data-quality tag. never-fabricate: omit lat/lon when None.

## Consumer runtime/batching semantics (the tight design)

A consumer SELECTS from an already-produced set; it does not capture. Old time-sampler
params (`--interval`, `--max-runtime`) do NOT map cleanly — a consumer has TWO
independent clocks that must never be conflated:
- **A — batch cadence** (`--batch-interval`): how often the plugin WAKES. 0 = single-shot.
- **B — sampling stride/policy** (`--select` + `--select-stride`): which frames it
  PICKS once awake.
"Consume every 15m, batch at 1h" = wake hourly, pick 15m-spaced frames since last wake.

Selection cases (the *semantics* — see CLI section below for final flag names):
- newest — single newest unseen frame (v1 default exemplar).
- newest-k — K newest unseen (a count cap).
- stride — one frame every D of CAPTURE-time (deterministic).
- all-unseen — every not-yet-seen frame in the cache (a count cap prevents a backlog storm).

## CLI surface: consolidate when extending a v1 plugin (design lesson)

Bolting cache mode onto an inherited standalone CLI produces flag sprawl (~25 flags)
with three recurring confusions — AUDIT the combined surface before writing code
(a new-repo v2 makes breaking the old CLI free, so fix it now, don't carry ambiguity):

1. **Overlapping timing flags.** v1 had `--interval` (self-capture spacing, meaningless
   without a camera) + `--continuous Y/N` + `--max-runtime`; adding a wake cadence made
   four. `wake-cadence 0` ALREADY means single-shot, so `--continuous` is redundant.
   → collapse to `--every <dur>` (0 = single-shot) + `--max-runtime <dur>`.
2. **Inferred-mode input flags.** `--stream`/`--snapshot-url`/`--image-dir`/`--from-cache`
   are mutually exclusive but the mode was inferred by precedence (set two → silent
   surprise). → one explicit `--source {cache,stream,snapshot,image-dir}` + `--input`.
3. **Conditionally-valid flags.** A `--select {enum}` + companion `--select-stride`
   (only meaningful for one enum value) + `--max-batch` (meaning varies per policy) are
   invisible-in-help footguns. → one CONTINUOUS knob `--select-every <dur>` (0 = newest,
   D = stride, `--max-frames K` = newest-K) + a scoped boolean `--all-unseen`. Always
   meaningful, no dead companion flag.

Final clean set (11 sprawl flags → 6): `--source`+`--input`, `--every`+`--max-runtime`,
`--select-every`+`--max-frames`+`--all-unseen`. Plus argparse ARGUMENT GROUPS in --help
(Source / Schedule / Selection / Memory / Detection / Output) and a validation layer
that warns/rejects incoherent combos (e.g. `--select-every` set for `--source stream`).
Worked example in the clean CLI: `--source cache --input <dir> --consumer-id human
--classes person --every 15m`. General principle: prefer ONE explicit mode selector +
ONE continuous knob over several inferred/enum/conditionally-valid flags.

Two windowing models kept distinct: time-windowed (newest/newest-k/stride:
capture_ts > last_wake) vs backlog (all-unseen: whole cache). **Seen-store dedup is
the universal safety net** applied after either, so switching selection mid-life is safe.

**Seen-memory** ("what I've examined"):
- Key = **unique_id (SHA256), NOT capture_ts** — stable across producer restarts,
  re-scans, mtime changes, monotonic-ts resets. ts as a key is WRONG.
- Consuming is **non-destructive** — file stays in cache (Layer-2 owns eviction);
  seen-store is a private bookmark, never a delete.
- Bounded/pruned to a horizon (cache is bounded → useful seen-set is bounded).
- Seen-store LOCATION — **RESOLVED (2026-07)**: it MUST be node-persistent (a
  one-shot scheduled run = fresh pod each fire; `/tmp` is pod-ephemeral so it starts
  blank and re-processes the whole cache → `all-unseen`/`stride` semantics collapse).
  The only persistent plugin-writable path is `/local-cache` — BUT the cache
  manager's node-wide backstop (`sweep()` pass 2) walks the WHOLE root and evicts the
  oldest file by mtime with no filter, and a rarely-touched append-only seen-store is
  exactly the oldest file → silently wiped under disk pressure. FIX shipped in
  `wes-local-cache-manager` v0.2.0: a **reserved state area** `RESERVED_STATE_DIRNAME`
  (default `.state`) → `/local-cache/.state/<plugin>/` is NEVER counted toward a cap
  and NEVER evicted (pruned in both `files_by_age` AND `cache_units`). So the seen-
  store lives at `<cache-root>/.state/<plugin>/seen`; `/local-cache` is the single
  durable home for frames AND consumer state, no extra mount. Consumer fails soft
  (warn + in-memory dedup for the run) if the reserved area isn't writable (older mgr).
- Seen-store FORMAT — **DECIDED (2026-07)**: newline-delimited hex SHA256s, one
  unique_id per line, plain text (crash-safe append: a torn final line just skips;
  trivially greppable/debuggable; prune by rewrite). sqlite considered and rejected as
  over-engineered for a bounded append-mostly set.
- Seen-store KEYING — **multi-instance safe (composite key)**: keying by plugin name
  ALONE collides when >1 consumer of the same family runs (two YOLOs: one counting
  humans, one hummingbirds; or different thresholds/cameras). Path is:
  `/local-cache/.state/<plugin>/<consumer-id>/<cache-name>/<camera>/seen` where each
  segment answers a distinct question — plugin family / which instance / which
  producer stream. Identity = (which instance) × (what it consumes).
  `<consumer-id>` must satisfy TWO competing requirements at once: STABLE across pod
  restarts (so one-shot persistence survives) yet DISTINCT between instances (no
  clobber). Derive it from `WAGGLE_JOB_NAME`+`WAGGLE_TASK_NAME` (same env
  image-sampler2 uses for provenance → consistent across the producer/consumer pair);
  fall back to `WAGGLE_APP_ID` (pod UID) ONLY if job/task unset — WITH A WARNING,
  because a UID changes every pod and thus loses cross-restart memory (the exact trap
  `.state` was built to avoid). `--consumer-id` overrides for a human-readable stable
  name (e.g. `human`, `fast-hummers`) an operator controls. Note `--consumer-id` is
  independent of cadence (`--batch-interval`) and classes (`--classes`) — it names the
  memory, nothing else.
  Sharing semantics: DEFAULT = separate stores (distinct job/task → separate memory) =
  "two different analyses of one stream," each independently processes every frame.
  SHARED `--consumer-id` = N identical instances COOPERATIVELY divide one cache (each
  frame once, whoever grabs it first); dedup is ADVISORY not a lock (worst case a
  frame processed twice on concurrent wakes; no cross-instance locking in v1).

**Fail-fast, no discovery for v1:** cache-root ABSENT → hard error (mirror
image-sampler2 `assert_cache_root_available`, no silent /tmp fallback — that fallback
was REMOVED at image-sampler2 v0.5.1). Empty-dir-but-present → valid, process nothing.
Cache discovery/announcement is deferred (IS-5 in plugin-improvements.md); v1 is told
the path explicitly (`--source cache --input <root>/<cache-name>/<camera>`), producer+
consumer agree on cache-name by job config.

Edge cases to test: consumer-faster-than-producer (dedup → zero-frame wakes OK);
frame evicted mid-select (skip like mid-scan disappearance, don't crash); corrupt/
missing seen-store (treat empty, worst case reprocess once, never block on bookmark I/O).

## Building a v2 consumer plugin from a v1 standalone (the recipe)

1. Copy the standalone repo verbatim to `<name>2/` (rsync --exclude .git/.venv), fresh
   `git init` (new lineage, not the v1 history), same author convention.
   **SECRET-SCRUB BEFORE FIRST PUSH (learned the hard way 2026-07):** a verbatim v1
   copy can inherit committed secrets — e.g. sage-yolo's `jobs/*.yaml` carried a LIVE
   cleartext camera cred (`user=sage&password=CAMERA_PASSWORD`). BEFORE creating the public
   repo, scan TRACKED files (`git ls-files -z | xargs -0 grep -niE
   'password=[^&"' ]|ghp_[A-Za-z0-9]{20}|BEGIN.*PRIVATE KEY|<PRIVATE_EMAIL_DOMAIN>'`) and
   redact to a placeholder (`password=REPLACE_ME`). If the secret is already in a
   commit (e.g. the baseline commit), a later redaction commit is NOT enough — the
   secret is still in history; rewrite it out (`git filter-branch --tree-filter 'sed
   -i s/SECRET/REPLACE_ME/g <files>' -- --all`), delete `refs/original/`, reflog
   expire + `gc --prune=now`, then `push --force`; VERIFY `git log origin/master -p |
   grep -c SECRET` == 0 on the REMOTE. Note: the SAME leak still lives in the public
   v1 repo it was copied from → flag rotation + v1 history scrub to the user.
2. Write a `V2-Design.md` FIRST (thesis, current-state gaps, decisions locked with
   leans, scaffolding features to use, consumer semantics, staged plan). Iterate the
   doc with the user BEFORE touching app.py — keep the baseline a clean verbatim copy.
3. Vendor `node_info_env.py` (single file, no deps) rather than pip-depending, until
   pywaggle2 is pip-installable — matches image-sampler2. Note the sync obligation.
   **CRITICAL — do NOT vendor it under a repo-root `waggle/` package** (see Stage-3
   lessons): that shadows the installed pywaggle and breaks `from waggle.plugin import
   Plugin`. Vendor at repo ROOT as `node_info.py` and import `from node_info import
   read_node_info`.
4. Stage the build (each gated GREEN, mirrors image-sampler2): cache-read+fail-fast →
   frame metadata → node identity → seen-memory → batching/select → jobs+docs+Docker
   → on-node e2e. Success bar = producer writes, consumer processes WITHOUT a camera,
   published records carry VSN+GPS, loop bounded by the manager (proves cross-user
   cache read, the open gap in wes-local-cache-manager/HANDOFF.md).

## A consumer that ALSO produces: the detect→classify cascade (crop-producer pattern)

A powerful extension of the cache pattern: a GPU consumer (e.g. yolo2) can ALSO
become a PRODUCER by writing derived frames back into a NEW cache stream, so a
downstream classifier (e.g. bioclip) consumes each derived object. Example:
yolo2 detects birds, CROPS each bbox, writes each crop as its own v2 frame into
`<camera>-crop`; bioclip reads those crops for species-level classification.
This is a **detect→classify cascade mediated entirely by the shared cache — no
cross-plugin triggering code, no watcher RPC** (it replaces the fragile
"detector-continuous + classifier-gated-in-the-watcher" coupling).

Why it composes cleanly: the downstream classifier needs ZERO changes IF the
derived frames are written in the IDENTICAL v2 format it already consumes (same
filename scheme + EXIF/UserComment metadata — see "The self-describing cached
frame" above). So the whole job of "become a producer" is: emit byte-compatible
v2 frames into a bounded ring, exactly as image-sampler2 does.

Design rules for the producing side (grounded in reading image-sampler2's
metadata.py/cache.py; a detection dict from the detector is
`{"class", "confidence", "bbox":[x1,y1,x2,y2]}`):

- **Inherit the SOURCE frame's `capture_ts_ns`** for every derived frame — a
  species result must stay frame-anchored to when the photo was TAKEN, not when
  the crop was cut. Same never-fabricate identity rules apply (vsn/node_id/GPS
  from the parent frame's resolved identity).
- **Own output stream, own ring bounds.** Write to `<root>/<out-cache-name>/
  <camera>-crop/` with its OWN `--crop-max-count`/`--crop-max-mb`. Never mix
  derived frames into the raw stream. Producer/consumer RATE RULE still holds:
  the classifier must drain the crop ring faster than the detector fills it, or
  crops evict before classification (same trap as the raw cache).
- **Multiple matches per frame → multiple derived frames.** N birds in one frame
  = N crops = N cache entries. They share the parent `capture_ts_ns`, so
  disambiguate with a `detection_index` in `object_name`/metadata — otherwise
  they collide on filename.
- **Separate the "produce" gate from the "upload for humans" gate.** The
  confidence bar to hand a crop to a species classifier is a DIFFERENT decision
  than the bar to save an annotated image for a human. Use an INDEPENDENT flag
  (`--crop-match "bird:0.5"`, same grammar as `--save-match`), default empty=OFF
  so the whole feature is purely additive (no behavior change when unset).
- **Pad the crop.** Classifiers do better with a little context than a razor-tight
  box — `--crop-padding 0.15` (fraction of bbox, clamped to image bounds). Also
  consider a min-size floor (skip/upscale sub-32px crops) — a distant subject
  yields a tiny useless box.
- **Carry provenance INTO the derived frame's v2 JSON:** `source_class`,
  `source_confidence`, `source_bbox`, `source_unique_id` (the PARENT frame's
  uid). Cheap, and it lets a downstream species result be traced back to the
  exact parent frame + box. The classifier's seen-store keys on the CROP's own
  unique_id (SHA256 of crop bytes) — distinct per crop, so each is processed once.
- **Publish a count** (`env.crop.count` per frame, frame-anchored) so crop
  activity is observable in the data plane without node access.
- **Wire it at ONE call site**, right after `detect()`, alongside the existing
  publish/upload calls, as a no-op when the crop flag is empty. Give the
  image-dir and live paths the same call for test/standalone parity.

DRY choice for the v2 WRITER (metadata.py + cache.py ring/eviction): either
extract a SHARED module both plugins vendor, or VENDOR A COPY into the consumer
repo (matching the `save_match.py` / `node_info.py` byte-identical precedent).
Vendoring isolates the feature-add from the producer's repo; a shared module is
cleaner long-term. Resolve before building the writer stage.

Version this as a MINOR bump (additive, off-by-default) — it never disturbs the
validated counting/consuming path. Stage it like any cache work: design doc →
vendored/shared writer (+ v2-name/EXIF/eviction round-trip tests) → crop logic
(geometry/clamp/multi-detection/off-by-default no-op tests) → count+provenance →
offline e2e (test image with N objects → N valid v2 crops readable by the SAME
`read_frame_metadata` the classifier uses) → on-node e2e (live cam → crops →
REAL classifier → species records in the data API) → docs+bump+commit.
(Full worked draft: sage-yolo2 `CROP-PRODUCER-Design.md`, 2026-07.)

## Building a SECOND consumer by vendoring the skeleton from the FIRST (verified 2026-07-15)

Once one v2 consumer exists (sage-yolo2), the next one (sage-bioclip2, a species
classifier) is mostly ASSEMBLY, not invention: graft the new model's inference
brains onto the proven cache-consumer skeleton. Verified building sage-bioclip2 =
sage-bioclip v1's `BioCLIP2Classifier` (pybioclip) grafted onto sage-yolo2's v2
wake loop; 91 offline tests green, first try after two small fixes.

- **Vendor the whole cache-consumer SKELETON byte-identical from the sibling
  plugin, not just node_info from pywaggle2.** `consumer.py`, `selection.py`,
  `seenstore.py`, `node_info.py`, `save_match.py` are all MODEL-AGNOSTIC — they
  ARE the v2 read contract. Copy them verbatim (`sha256sum` both sides to prove
  identity), carry over their unit tests unchanged (they pass as-is: ~85 tests),
  and record the sibling as the vendor source in `VENDORED.md` with the same
  tests-are-the-contract sync obligation as crop_writer. Only `app.py`'s
  detector/classifier class + the publish topic names are model-specific.
- **The ONLY model-specific code:** swap the detector class for the classifier
  class (lift verbatim from the v1 model plugin), swap `detect()`+count/crop
  publish for `classify()`+`env.species.*` publish, keep the identical wake loop
  (scan→select→read meta+identity+provenance→infer→publish frame-anchored→mark
  seen). Lift annotation/`--save-match` from v1 too.
- **CONSUMING CROPS = a single `--input` path change, no mode flag, no branch.**
  Because image-sampler2 frames and yolo2 crops are the IDENTICAL v2 format, the
  same classifier plugin reads either the raw stream
  (`--input /local-cache/hummingcam/top`) or a crop stream
  (`--input /local-cache/hummingcam-crops/top-crop-0`) with zero code difference.
  Do NOT add a `--mode full|crop` flag — it would be redundant surface. PROVE
  it's config-only with a test that runs the identical wake code on both a plain
  v2 frame AND a crop-with-`source{}` and asserts both publish a species record.
- **Read the crop's `source{}` provenance and attach it to the downstream
  record** (`_read_source_provenance(frame)` → the nested `source` dict from the
  UserComment JSON, or None on a plain frame). Surface `source_class`/
  `source_confidence`/`source_unique_id` on the species record's meta so a
  species result traces back to the YOLO detection AND the parent frame. Harmless
  no-op on full frames (no `source` key). Dedup on the CROP's own `unique_id`.
- **PITFALL — a non-idempotent library patch must run ONCE at Docker BUILD time,
  never re-imported at runtime.** sage-bioclip's `patch_pybioclip.py` edits
  pybioclip internals to enable BioCLIP-2.5 (ViT-H/14) and `assert`s the PRISTINE
  source string — so running it twice raises `AssertionError`. v1 applies it in
  the Dockerfile (`RUN python3 /tmp/patch_pybioclip.py`) and app.py does NOT
  import it. My first draft imported it at runtime in `load()` → would re-run the
  patch on already-patched source and crash the pod at model load. FIX: apply the
  patch only in the Dockerfile; app.py imports the patched library directly. When
  grafting from a v1 plugin, CHECK how v1 applies any monkeypatch (build-time vs
  runtime) before copying its import structure — grep the v1 app for the patch
  import; if absent, the patch is build-time-only.
- **Pin the patched library's exact version.** The patch matches specific source
  lines, so `requirements.txt` must pin the version it was written against
  (`pybioclip==2.1.5`), not `>=`. A minor bump can move the asserted lines and
  break the patch.
- **The deploy-sideload.sh script + Dockerfile pattern port verbatim** — the
  script reads name/namespace/version from sage.yaml (nothing hardcoded), and the
  Dockerfile is the same CUDA base + torch-freeze + model-predownload-before-COPY
  layering (swap the model-download RUN line for the new model). First release of
  a re-architected plugin = version 2.0.0 (mirrors yolo2's v1→2.0.0 jump).

## Stage-1 implementation lessons (cache read + fail-fast — verified 2026-07)

Concrete patterns from building sage-yolo2's `consumer.py` (Stage 1 shipped, 51 tests
green). Reuse for any consumer's read side:

- **Put the read side in a PURE module** (`consumer.py`) — NO cv2 / YOLO / pywaggle
  imports. Then the whole cache contract (resolve, fail-fast, parse, select) is
  unit-testable OFFLINE with no GPU. The camera/inference code stays in app.py; the
  consumer module is stdlib-only. This is what makes a fast pytest suite possible on a
  repo whose only inherited test needs a GPU.
- **Mirror image-sampler2's exact API shape** so producer+consumer stay in sync:
  `resolve_cache_root()` precedence = `explicit > $IS2_CACHE_ROOT > /local-cache`
  (SAME env var as the producer); `assert_cache_available()` = fail-fast on absent/
  unreadable dir with a rich operator message (explain the wes-local-cache-manager
  mount), present-but-empty is VALID (returns None, not an error); `parse_v2_name()`
  anchors on the FIRST `-v2-` marker (ts is all-digits so it delimits cleanly even
  when vsn/camera contain hyphens — `rest.split("-", 1)` is correct for hyphenless
  vsn, the common case); `scan_frames()` sorts by `(capture_ts_ns, name)` and skips
  `*.tmp` + non-v2 + non-files.
- **THE load-bearing test = ts-not-mtime ordering.** Write the newest-CAPTURE_TS file
  FIRST then `os.utime(path,(1,1))` to give it an ancient mtime, write an older-ts
  file second (newer mtime); assert `newest_frame()` still returns the ancient-mtime
  one. This is the single test that proves you didn't accidentally order by mtime —
  the most likely silent bug. Also test: empty-dir→None vs absent-root→CacheError,
  `*.tmp`/non-v2/subdir ignored, parse rejects (empty ts/rest, non-digit ts, ts<=0,
  wrong ext).
- **Self-bootstrapping `make test`** for a repo that shipped only a GPU integration
  test (tests/run-tests.sh): add a Makefile whose `test` target creates a throwaway
  venv (`.venv-test`, gitignored), pip-installs pytest, and runs the OFFLINE unit
  files only. Matches the other pywaggle2 repos' convention and the user's
  "works out-of-the-box, no manual venv" preference. Keep the GPU test separate.

## Stage-2 implementation lessons (frame metadata reader — verified 2026-07)

Reading the self-describing frame's authoritative metadata (sage-yolo2 Stage 2, 60
tests green). Reuse for any consumer's metadata read side:

- **Metadata AUTHORITY split (decided by reading the producer's metadata.py):**
  (1) capture_ts -> filename prefix (the ordering key); if UserComment JSON's
  `capture_timestamp_ns` differs, WARN + PREFER THE FILENAME (a mismatch = corrupted/
  edited file, not ambiguity -- do NOT skip the frame). (2) GPS lat/lon -> read from
  the **UserComment JSON (plain SIGNED decimal floats)**, NOT reconstructed from GPS
  EXIF. The producer canNOT store negative lat/lon in EXIF (piexif raises struct.error),
  so GPS EXIF holds `abs(deg)` DMS + a separate N/S/E/W ref -- needing reconstruction
  the JSON avoids. Frame the EXIF as the TOOL-FRIENDLY view (photo browsers / mapping
  tools that drop a map-pin from EXIF), JSON as AUTHORITATIVE for machine reads. Docs
  MUST state this split. (3) vsn/camera -> JSON authoritative, filename best-effort
  fallback. (4) GPS is OPTIONAL -> omit-never-fabricate: no fix means no GPS block +
  `lat/lon: null`; expose `has_location` and drop location from the record entirely,
  never invent it.
- **Reader is Pillow-ONLY at runtime; piexif is TEST-only.** Read the UserComment tag
  via Pillow (already a plugin dep): `im.getexif().get_ifd(0x8769).get(0x9286)`
  (ExifIFD -> UserComment 0x9286), strip the 8-byte `b"ASCII\x00\x00\x00"` prefix,
  `json.loads` the rest. Do NOT add piexif to requirements.txt -- the reader doesn't
  need it; keeping it out keeps the runtime dep surface minimal.
- **THE load-bearing test = cross-library round-trip.** The producer writes the
  UserComment with **piexif**; the consumer reads with **Pillow**. Prove they agree:
  in tests, generate REAL producer-format JPEGs with piexif (same ASCII prefix +
  `json.dumps(sort_keys=True, separators=(",",":"))` embed), then read them back with
  the consumer's Pillow path and assert every field -- ESPECIALLY signed NEGATIVE
  lat/lon (southern/western hemisphere), the exact GPS-sign landmine. Also test:
  no-UserComment->filename fallback, corrupt-JSON->fail-soft (warn, ts still usable),
  ts-mismatch->warn+prefer-filename, partial-GPS (one of lat/lon null)->has_location False.
- **Fail-soft on all metadata reads** -- any error (no EXIF, bad prefix, bad JSON) ->
  return the filename-derived fields + None for the rest, log a warning, let inference
  proceed. Never block a detection on bookmark/metadata I/O.

## Stage-3 implementation lessons (vendored node identity + cross-check — verified 2026-07)

Wiring the pod's own identity and cross-checking it against the frame's (sage-yolo2
Stage 3, 73 tests green). Reuse for any consumer.

- **VENDORING FOOTGUN — do NOT put the vendored reader under a repo-root `waggle/`
  package.** The obvious move ("vendor `waggle/data/node_info_env.py` byte-identical")
  creates a repo-root `waggle/` that SHADOWS the installed pywaggle on `sys.path`, so
  `from waggle.plugin import Plugin` / `from waggle.data.vision import Camera` (which
  app.py needs) resolve to the empty vendored package and break — verifiable via
  `python -c "import waggle.data; print(waggle.data.__path__)"` pointing only at the
  repo dir. FIX: vendor at repo ROOT as `node_info.py`, import `from node_info import
  read_node_info`. image-sampler2 avoided the same collision by mirroring the contract
  in a repo-root `nodemeta.py` rather than shadowing `waggle/`. After vendoring, VERIFY
  installed pywaggle still resolves from site-packages.
- **Vendor = content-identical + provenance header + a VENDORED.md.** Copy the body
  byte-for-byte, prepend a header comment recording source repo/version/commit and the
  sync obligation, and add a `VENDORED.md` with a one-line diff command to re-verify
  sync (`diff <(tail -n +<hdr+1> node_info.py) <(tail -n +2 <src>)`, skipping each
  file's header/shebang). Bump the ref when re-vendoring.
- **Frame identity is AUTHORITATIVE; pod identity is cross-check + fallback**
  (`resolve_identity(frame_meta, node_info)`): vsn/node_id prefer the FRAME's (it's what
  the pixels are), fall back to the pod's only for fields the frame lacks. If BOTH have
  a vsn and they DIFFER, WARN (stale/mislabeled cache) but STILL attribute with the
  frame's. Location: frame GPS -> pod GPS -> none, and record a `location_source`
  ("frame"/"node"/None) tag; NEVER fabricated. `get_node_info()` is fail-soft (missing
  reader != stopped inference). Accept an injectable `node_info=` param so the whole
  cross-check matrix is unit-testable without setting real WAGGLE_NODE_* env (and in the
  `node_info=None` real-env test, `monkeypatch.delenv` the 5 vars for determinism).
- **Test the vendored reader's sentinel normalization directly** (parity with source):
  empty-env -> all-None + mobility "unknown" + vsn_is_placeholder True; vsn "0" ->
  None/placeholder; GPS "999" -> None by RANGE check; signed southern/western coords
  pass through.

## Stage-4 implementation lessons (seen-memory store — verified 2026-07)

Building the durable dedup store (sage-yolo2 Stage 4, 87 tests green). Reuse for any
consumer. (Design decisions — format/keying/location — are in the Seen-memory section
above; these are the CODE patterns.)

- **Own module, one concern** (`seenstore.py`, stdlib-only) — like `save_match.py`,
  `node_info.py`. Keeps `consumer.py` from bloating; matches the repo's module-per-
  concern style. `SeenStore`: load the file ONCE into an in-memory set at construction
  (O(1) `is_seen`), APPEND each new id on `mark`, PRUNE to a horizon by atomic rewrite
  (`open(tmp,'w')` + `os.replace`) when over `max_ids`. `seen_store_path()` is a PURE
  path builder (composite key) tested independently of any file I/O.
- **`--reprocess` records but reports unseen.** `is_seen()` returns False under
  reprocess (so every frame is processed) BUT `mark()` still writes the id — so toggling
  reprocess back OFF resumes correct dedup. Test this explicitly (reprocess run marks,
  then a fresh non-reprocess instance sees the id).
- **Fail-soft on ALL store I/O** — missing file (FileNotFoundError -> empty, first run),
  unreadable/corrupt (warn -> empty), unwritable append/prune (warn, never raise),
  blank lines skipped, duplicate lines deduped on load, empty-id never stored. Worst
  case = reprocess once; never block inference on bookmark I/O.
- **Node-persistence is THE test** (`test_survives_reload`): mark ids in one instance,
  construct a FRESH SeenStore on the same path (= new pod), assert it sees them. This
  is the whole point (`.state` reserved area survives eviction; `/tmp` would not).

## Stage-5 implementation lessons (batching & selection — verified 2026-07)

The pure core of the wake loop (sage-yolo2 Stage 5, 114 tests green). The wake LOOP
itself (YOLO + publish + sleep) stays in app.py; the SELECTION is a pure function.

- **`select_frames()` is pure and injectable.** Takes the oldest-first frame list +
  `last_wake_ts_ns` + `select_every_ns` + `all_unseen` + `max_frames` + `seen` +
  `reprocess` + **`uid_of=` callable**. The `uid_of` injection is the key move: the
  real loop passes a fn reading the frame's resolved SHA256 unique_id, but tests pass
  a lambda over a stub attribute — so selection stays GPU/metadata-free and unit-
  testable while the loop still dedups on the true SHA256. Two windowing models kept
  distinct in code: backlog (`all_unseen` -> whole list) vs time-windowed
  (`capture_ts > last_wake_ts_ns`); dedup + cap applied after either.
- **BUG CAUGHT: newest-K needs `window[-K:]`, not a post-cap.** `--select-every 0
  --max-frames K` must select the K NEWEST. A naive newest branch takes only
  `window[-1:]` then step-4 caps to K -> yields 1 frame, not K. FIX: add an explicit
  branch `elif max_frames and max_frames > 1: candidates = window[-max_frames:]`. For
  stride/all-unseen, `max_frames` remains the OLDEST-first drain cap (`[:max_frames]`)
  so a first-run backlog drains over wakes, no storm. These two meanings of max_frames
  (K-newest selector vs oldest-first drain cap) are correct and must both be tested.
- **TEST ARTIFACT: never use `capture_ts=0` in stride/window tests.** Real capture_ts
  are huge ns epochs and `parse_v2_name` rejects ts<=0, but the default
  `last_wake_ts_ns=0` filter is `capture_ts > 0`, which silently DROPS a t=0 frame and
  makes stride tests fail confusingly (`[10,30]` not `[0,20,40]`). Use realistic
  non-zero bases (100,110,120...). Not a code bug — a test-fixture footgun.
- **Stride is capture-ts anchored (deterministic).** `_stride_pick` walks oldest->
  newest, always takes the first, then each next frame >= stride_ns after the last
  PICK (not the last frame). Test uneven spacing to prove it anchors on capture-time,
  not frame count.
- **`parse_duration`** accepts `s/m/h` suffix or a bare number (= seconds); `0` is the
  single-shot/newest sentinel; garbage raises ValueError.

## Crop-producer Stage-1 lessons (the vendored v2 WRITER — verified 2026-07)

Building the WRITE side that turns a consumer into a producer (sage-yolo2
crop-producer Stage 1, 132 tests green). Reuse for any consumer gaining a
produce role. (Design/decisions are in the cascade section above; these are the
code patterns.)

- **Vendor a COHESIVE write module, not image-sampler2's files verbatim.** The
  consumer repo already has its OWN pure v2-name parser + metadata reader
  (`consumer.py`, the read side). So the vendored WRITER only needs the write
  half: EXIF embed (from `metadata.py`) + ring/eviction (from `cache.py`),
  combined into one `crop_writer.py` (`build_v2_name`, `embed_all`, `scan_ring`,
  `plan_evictions`, `commit_capture`, `write_frame`). Do NOT drag in the read-side
  duplicates — reuse the repo's existing reader. Add a header recording the source
  + the manual-sync obligation (same precedent as `save_match.py`/`node_info.py`).
- **Provenance as a NESTED `source` object, not flat top-level fields.** Put
  `source_class/confidence/bbox/unique_id` + `detection_index` under a single
  `"source"` key in the v2 JSON. This keeps a plain image-sampler2 frame and a
  derived crop frame sharing the IDENTICAL base schema; a classifier reads
  `source` only when present. Flat fields would fork the schema.
- **THE load-bearing test = crop-readable-by-the-real-reader.** Write a crop with
  `crop_writer.embed_all` → save under its v2 name → read it back with the repo's
  OWN `consumer.read_frame_metadata` (== exactly what the downstream classifier
  uses) and assert every field incl. signed GPS. This is the single test that
  proves byte-compat between the new write side and the existing read side; a
  format drift here silently breaks the whole cascade.
- **BUG CAUGHT by the eviction test: `write_frame` on an E3 drop passes
  `tmp_path=None` into `commit_capture`, which called `os.remove(None)` →
  TypeError.** Fix: `_safe_remove` (and any drop-new path) must no-op on
  `path is None`. The E3 oversized-drop branch never created a tmp, so there's
  nothing to remove. Always test the E3 path (`--crop-max-mb` below one frame's
  size → nothing written, ring stays empty).
- **`write_frame` = scan → plan → atomic tmp(fsync) → commit, one call.** Encode
  the full ring write as a single function so app.py's crop call site is one line.
  tmp is `os.open(O_CREAT|O_TRUNC)` + `os.write` + `os.fsync` + `os.close`, then
  `commit_capture` evicts-first then `os.replace` — the ring never transiently
  exceeds caps and no torn file exists under a final name.
- **Wire the new test file into `make test`** (add `tests/test_crop_writer.py` to
  the target) — the self-bootstrapping venv already has Pillow+piexif+numpy.

## Crop-producer Stage-2 lessons (wiring crop logic into app.py — verified 2026-07)

Wiring the detect→crop step into the runtime (sage-yolo2 crop-producer Stage 2,
139 tests green). Reuse for any consumer's produce side.

- **Off-by-default = one guard at the top of the produce function + threaded
  `crop_rules` through every source path.** Parse `--crop-match` with the SAME
  `parse_save_match` grammar as `--save-match` (empty list = OFF). `_maybe_produce_crops`
  returns 0 immediately when `crop_rules` is falsy, so the validated count/upload
  path is byte-for-byte unchanged when the feature is unused. Add the call at ALL
  THREE source sites (cache / image-dir / live) right after `_maybe_upload`, as a
  keyword-only `crop_rules=None` param — the cache path additionally threads the
  parent frame's `unique_id` in as `source_uid` provenance (the other paths pass "").
- **Geometry: pad→clamp→min-px floor, in that order, returning None on degenerate.**
  `_pad_clamp_bbox(bbox, w, h, padding)` pads by `round(bbox_size * padding)` each
  side, clamps to `[0,w]×[0,h]`, returns None if the clamped box has zero area.
  Apply the `--crop-min-px` SHORT-SIDE floor AFTER clamping (a box near an edge
  shrinks when clamped) and SKIP (log + continue) rather than upscale a tiny box.
  Test edge-clamping (box at 0,0 with big padding stays ≥0), degenerate→None, and
  the min-px skip explicitly.
- **Per-crop fail-soft.** Wrap each detection's crop+encode+embed+write in
  try/except that logs and continues — one bad crop must never crash the wake or
  lose the other crops in the same frame. `cv2.imencode` returning `(False, _)` is
  handled the same way (log + skip).
- **TEST FRAGILITY — the shared-`sys.modules['cv2']`-stub bites across test FILES.**
  Two test files both stub cv2 into `sys.modules` before `import app`; app binds
  cv2 ONCE (whichever file imports it first wins), and pytest imports ALL test
  modules before running any test — so a later file's fresh cv2 stub can REPLACE an
  earlier one, and the crop test's `cv2.imencode` (or the cache test's `imread`
  semantics) goes missing depending on file order. Symptom: tests pass alone and in
  one order but fail in the reverse order (`module 'cv2' has no attribute
  'imencode'`). FIX: make every cv2-stubbing test file install a stub that is
  MUTUALLY COMPATIBLE — reuse the existing `sys.modules.get("cv2")` object if
  present, and set stub methods that satisfy BOTH files (e.g. `imread = lambda p:
  "IMG" if os.path.exists(p) else None` shared verbatim; add `imencode` returning
  REAL JPEG bytes via PIL so the crop's embed gets valid input). VERIFY BOTH
  ORDERINGS explicitly (`pytest a.py b.py` AND `pytest b.py a.py`), not just
  `make test`'s fixed order — a stub-sharing bug hides in the alphabetical default.
- **To make crop bytes REAL in tests, stub `cv2.imencode` via PIL:**
  `Image.fromarray(img[:, :, ::-1]).save(BytesIO(), "JPEG")` → `np.frombuffer(...)`.
  Then the crop written by the produce path is a byte-real v2 JPEG readable back by
  the repo's own `consumer.read_frame_metadata` — the same load-bearing compat proof
  as Stage 1, now through the full app.py call site. Frame is a real numpy array
  (`np.full((h,w,3),128,uint8)`) so `.shape` and `img[y1:y2,x1:x2]` slicing work.

## Stage-6 implementation lessons (integration: app.py loop + jobs + docs + Docker — verified 2026-07)

Wiring the pure modules into the real plugin runtime (sage-yolo2 Stage 6, 120 tests
green). This is where the offline suite stops covering everything — GPU/pywaggle enter.

- **OFFLINE-TEST THE WAKE LOOP by stubbing the heavy imports in `sys.modules` BEFORE
  importing app.** app.py imports cv2/numpy/torch/ultralytics/waggle at module top, so
  you cannot import it in a GPU-free venv directly. In the test file, install
  lightweight `types.ModuleType` stubs into `sys.modules` for cv2 (imread returns a
  truthy sentinel / None if path missing; imwrite/rectangle/putText no-op), torch,
  ultralytics, `waggle`+`waggle.plugin`(Plugin)+`waggle.data.vision`(Camera) — THEN
  `import app`. Drive `_process_cache_wake(fake_plugin, fake_detector, ...)` on REAL
  cache JPEGs (piexif-embedded) with a FakePlugin (records publish/upload calls) and a
  FakeDetector (returns a fixed detection). This proves the whole pipeline wires end
  to end (scan->select->metadata->identity->publish frame-anchored->seen.mark) + dedup
  across wakes, all without a GPU.
- **DO NOT stub numpy** — install the REAL numpy in the test venv and stub only the
  genuinely-absent GPU libs. A fake `numpy` in `sys.modules` breaks `pytest.approx`
  (it probes `numpy.isscalar` etc.) across the ENTIRE session, failing unrelated tests
  in other files (module injection is global, order-independent at import time). numpy
  is small (unlike torch); adding it to the Makefile venv is cheap and correct.
- **DOCKERFILE FOOTGUN: COPY every new module.** A v1 Dockerfile that `COPY save_match.py
  . && COPY app.py .` will ship a BROKEN image once you split logic into new modules —
  it silently omits `consumer.py`/`selection.py`/`seenstore.py`/`node_info.py` and the
  container `ImportError`s at startup (never caught by the offline suite, which imports
  from the repo dir). After any module split, AUDIT the Dockerfile COPY list against the
  repo's top-level *.py. Add each vendored/new module explicitly.
- **VERIFY the README CLI reference 1:1 against argparse** (catches invented/omitted
  flags in doc-writing, esp. when delegated): `diff <(grep -oE '\"--[a-z-]+\"' app.py |
  sort -u) <(grep -oE '\\-\\-[a-z-]+' README.md | sort -u)`. Should match exactly
  (ignoring markdown `---` rules). Discharge the Stage-2 GPS-authority doc debt HERE:
  the README must state the UserComment-JSON-authoritative / GPS-EXIF-tool-view split.
- **Frame-anchored publish in the loop:** `_process_cache_wake` publishes with
  `timestamp=meta.capture_ts_ns` (observation time = capture time, NOT now()); adds
  vsn/node_id and (only when `identity.has_location`) signed lat/lon + location_source
  to meta — omit-never-fabricate carried all the way to the wire. `cv2.imread` returning
  None = frame evicted between select and read -> log + skip, don't crash (Layer-2 race).
  `seen.mark(meta.unique_id)` AFTER a successful frame.
- **consumer-id resolution lives in app.py** (`resolve_consumer_id(override)`):
  `--consumer-id` > `WAGGLE_JOB_NAME`+`WAGGLE_TASK_NAME` > `WAGGLE_APP_ID` (WITH warn:
  pod UID loses cross-restart memory) > "default" (warn). `parse_cache_input` splits
  `<root>/<cache-name>/<camera>` into the two trailing segments for the composite
  seen-store path. Both are pure and unit-tested (job/task pref, override wins, app-id
  fallback warns).
- **JOB YAML: the cache exemplar is a PRODUCER+CONSUMER PAIR in one spec.** The
  canonical v2 job lists TWO plugins under `plugins:` — image-sampler2 (`--stream <cam>
  --cache-name X --camera Y`) writing `/local-cache/X/Y`, and the consumer
  (`--source cache --input /local-cache/X/Y`) reading it — both `resource.gpu: true`,
  both scheduled. Migrate inherited standalone YAMLs to the new CLI (`--source
  stream|snapshot --input ...`) as FALLBACK examples, and re-run the secret-scrub
  (Recipe step 1) on every YAML before commit (passwords -> REPLACE_ME).
