# Deploying ARM64 plugins to Thor nodes (the working pipeline)

When the ECR portal build fails for a Thor/arm64 plugin, this is the
end-to-end path that actually works. Proven on H00F (Jetson Thor) for
yolo-object-counter, bioclip-species-classifier, and birdnet-species.

## CRITICAL: CPU-base and GPU/NVIDIA-base plugins have DIFFERENT ECR fate

There are TWO INDEPENDENT ECR build blockers. They were fixed on DIFFERENT
timelines, and conflating them will burn you (it did, 2026-07-10):

- **Infra #2 — buildkit `/proc/acpi` runc bug: FIXED 2026-07.** Affected EVERY
  plugin (arch-independent); every `RUN` step failed at container init. Once
  fixed, `RUN` steps start normally.
- **Infra #3 — QEMU crash on arm64 NVIDIA/CUDA base: STILL OPEN.** The
  ECR/Jenkins pipeline runs on x86_64 and cross-builds `linux/arm64` under QEMU
  (`buildctl ... --opt platform=linux/arm64`). NVIDIA CUDA base images
  (`nvcr.io/nvidia/pytorch:...`) hold aarch64 binaries QEMU can't emulate; `pip`/
  `import torch` aborts with `qemu: uncaught target signal 6 (Aborted)`, exit 134.

CONSEQUENCE — the branch that matters before you touch any deploy doc:
- **CPU-only plugins** (birdnet, `python:3.12-slim`, native wheels, no CUDA):
  #2 was their ONLY blocker → they **build in ECR now**. Standard "Register and
  Build" is the primary path (see `ecr-build-to-ses-cutover`).
- **GPU/NVIDIA-base plugins** (yolo, bioclip, `nvcr.io/nvidia/pytorch`): they hit
  BOTH #2 and #3. #2 is fixed but #3 is NOT → they **STILL fail in ECR** and
  STILL require native-Thor-build + k3s side-load (this file). There is **no
  native arm64 builder** yet.

HARD LESSON (do NOT repeat): a birdnet ECR success does NOT prove yolo/bioclip
will build. In 2026-07 the user believed "CI added a native arm64 builder";
docs were rewritten asserting ECR-primary for yolo; the v0.3.1 ECR build then
FAILED at exactly the QEMU `signal 6 / exit 134` step, and every ECR-primary
doc had to be reverted. Before rewriting a GPU plugin's docs to claim ECR
works: (1) check the plugin's base image — is it `nvcr.io/nvidia/...` or CUDA?
If so #3 applies. (2) TREAT "a native builder exists" as UNVERIFIED until an
actual ECR build of THAT plugin (or another NVIDIA-base one) succeeds. Do not
promote ECR to primary in docs on a belief; wait for the build to prove it.
Note: dropping `linux/amd64` from sage.yaml does NOT help — the crash is in the
arm64-under-QEMU path itself.

2. **`docker push` to the registry is denied.** A Sage portal access token
   authenticates to `registry.sagecontinuum.org` (login succeeds) but is
   read/pull-only: pushes return
   `denied: requested access to the resource is denied`.
   Registry writes are reserved for the Jenkins pipeline.

## Why the workaround works

SES pods on Thor use `imagePullPolicy: IfNotPresent`. If an image is
already present in the node's k3s containerd under the EXACT
registry-qualified name the job YAML references, the pod uses it without
ever pulling. Pod events show:
`Container image "registry.sagecontinuum.org/<ns>/<name>:<ver>" already present on machine`.

But SES validates the job's image against the ECR app **catalog**
(ecr.sagecontinuum.org) BEFORE scheduling — separate from the registry and
from the sideloaded image. If the catalog lacks the exact version, submit
fails with:
`[registry.sagecontinuum.org/<ns>/<name>:<ver> does not exist in ECR]`.

So you need BOTH: the image sideloaded into k3s (serves the pull) AND a
catalog metadata record (passes SES validation).

## The pipeline (run on the Thor node, e.g. ssh USER@node-<VSN>.sage)

```bash
# 0. PRE-BUILD SMOKE TEST (do this whenever you refactored startup/import code).
#    A 28GB build + sideload is a ~5+ min round trip; a startup crash wastes the
#    WHOLE cycle and then crash-loops in production. Catch import/parse/scope
#    bugs FIRST. Cheapest: byte-compile + parse locally (no image needed):
python3 -m py_compile app.py            # catches syntax errors
python3 -c "import ast,sys; ast.parse(open('app.py').read())"
#    Better, if the previous image version is still sideloaded, run the NEW code
#    through the OLD image's interpreter to exercise imports + arg-parse without
#    building (mount the repo, hit --help):
sudo docker run --rm --entrypoint python3 \
  -v ~/AI-projects/<repo>:/src \
  registry.sagecontinuum.org/<ns>/<name>:<PREV-ver> /src/app.py --help
#    Prints help -> imports/parse OK, safe to build. Traceback -> fix BEFORE
#    building. This would have caught the birdnet 0.1.5 `NameError: name
#    'birdnet' is not defined` crash-loop (a lazy `import birdnet` left in
#    __init__ after model load was moved to load()) before two wasted builds.
#    See references/plugin-duration-performance-telemetry.md for that case.

# 1. Build natively on Thor (arm64, no QEMU). Tag = FULL registry path,
#    must match the job YAML image: field exactly.
cd ~/AI-projects/<repo>
git pull
sudo docker build -t registry.sagecontinuum.org/<ns>/<name>:<ver> .

# 2. Sideload into k3s containerd (large images: 28GB bioclip ~3-5 min;
#    run in background and wait — it exceeds a 60s foreground SSH window).
sudo docker save registry.sagecontinuum.org/<ns>/<name>:<ver> \
  | sudo k3s ctr images import -

# 3. Verify present + CRI-managed (the label means k8s/SES can see it).
sudo k3s ctr images ls | grep <name>
#   ...:<ver> ... io.cri-containerd.image=managed

# 4. Register the version in the ECR catalog via API (NOT the portal).
#    See scripts/register-ecr-version.py in this skill. It clones an
#    existing version record and POSTs the new one.
python3 register-ecr-version.py \
    --namespace <ns> --name <name> \
    --from-version <existing-ver> --version <new-ver> \
    --git-url https://github.com/<owner>/<repo>.git \
    --token "$SAGE_TOKEN"

# 5. Create + submit the SES cron job (verified sesctl flags).
sesctl --server https://es.sagecontinuum.org --token "$SAGE_TOKEN" \
    create -f jobs/<job>.yaml          # -> numeric job id
sesctl --server https://es.sagecontinuum.org --token "$SAGE_TOKEN" \
    submit -j <job-id>

# 6. Verify it fires + publishes (one-shot pods vanish between ticks, so
#    check the data API, not kubectl).
curl -s -X POST https://data.sagecontinuum.org/api/v1/query \
  -H 'Content-Type: application/json' \
  -d '{"start":"-15m","filter":{"vsn":"<VSN>","name":"<measurement>"}}'
# Proof it is the SES job: meta.task == "<name>" (the job NAME, e.g.
# "insect-bioclip") and meta.plugin == "registry.sagecontinuum.org/<ns>/<name>:<ver>"
# (tail of meta.plugin is the version). NOTE: filter/group by meta.task and
# meta.plugin. There is NO meta.job key on these records — see the data-API
# meta-key pitfall below.
```

## Wrap the pipeline in one idempotent deploy script (do this per-repo)

Steps 1-5 above are 4-5 hand-run commands copy-pasted from a deploy doc every
release — error-prone and hostile to any downstream operator. Wrap them in a
single `scripts/deploy-sideload.sh` living in the plugin repo. Proven shape
(sage-yolo, 2026-07-11):

- **Default run = build -> import -> register** (steps 1-4, all idempotent so
  re-running is safe). **`--submit jobs/<file>.yaml` is opt-in** (step 5) so a
  double-run never double-submits an SES job.
- **Parse name/namespace/version/source.url straight from `sage.yaml`** —
  NOTHING hardcoded. A version bump then needs zero edits to the script (matches
  Pete's out-of-the-box rule: no hardcoded values forcing downstream edits).
  `--version` overrides for edge cases. Simple sed extractors work:
  `sed -nE 's/^version:[[:space:]]*"?([^"#]+)"?.*/\1/p' sage.yaml | head -n1`.
- **Auto-detect `--from-version`** by GETting the ECR catalog
  (`/api/apps/<ns>/<name>`) and picking the latest prior version. Fail with a
  clear message when the app has NEVER been registered (first version still
  needs one portal registration, or an explicit `--from-version`).
- **Drift check**: warn when any `jobs/*.yaml` `image:` tag != the sage.yaml
  version (catches the multi-place-edit trap where a bump misses a job file),
  and HARD-REFUSE `--submit` on a job whose image tag != the deployed tag.
- **Tokens demanded only by the step that uses them**: `SAGE_TOKEN` for
  register, `SES_USER_TOKEN` for `--submit`. Do NOT check them up front.

PITFALLS that bit me writing it (all caught by ad-hoc testing, fix before commit):
- **`--dry-run` must require NO tokens and hit NO network.** First cut put the
  `SAGE_TOKEN`/`SES_USER_TOKEN`/`need sesctl` guards BEFORE the dry-run branch,
  so `--dry-run` died on a missing token instead of just printing the plan.
  Gate every token check and binary-existence check behind `if DRY_RUN then
  print-plan else <real guards + action>`.
- **`set -euo pipefail` + a trailing `&&` one-liner leaks a non-zero exit.**
  A final `[ "$drift" -eq 1 ] && warn ...` evaluates false on the happy path,
  making the SCRIPT exit 1 on success. Use a full `if ...; then warn; fi` and an
  explicit `exit 0` at the end. Verify: clean run exits 0, drift-WARNING run
  ALSO exits 0 (drift is a warning not a failure), bad-arg exits 1.
- **NEVER pipe `k3s ctr images ls` into `grep -q` under `set -o pipefail` — it
  false-fails on SUCCESS (the nastiest bug of the whole script; only surfaced on
  live H00F, 2026-07-11).** The Step-2 post-import check was
  `sudo k3s ctr images ls | grep -q "$TAG" && ok ... || die "not found"`. The
  image WAS imported (verified 10.7 GiB, `io.cri-containerd.image=managed`), yet
  the script `die`d with "image not found." Cause: the images list is long;
  `grep -q` exits the instant it matches and SIGPIPEs the still-writing `ctr ls`;
  under `pipefail` that 141 becomes the pipeline's exit code, so `|| die` fires
  despite a match. FIX: capture first, then match in pure bash — no pipe, no
  SIGPIPE:
  `imgs="$(sudo k3s ctr images ls)"; if [[ "$imgs" == *"$TAG"* ]]; then ok; else die; fi`.
  Same class bites `... | grep -oE ... | head -n1` for the sesctl job-id parse —
  guard it with `|| true`. General rule: any `<big-producer> | grep -q|head`
  under pipefail can 141-false-fail; capture-to-var + bash matching is safe.
- **This SIGPIPE bug is invisible to `--dry-run` and the mktemp harness** —
  both SKIP the real `ctr images ls` check, so `bash -n` + dry-run + fixture
  tests all pass while the real deploy false-fails. LESSON: the FIRST real run
  on the node is the actual verification for a side-load script; a green dry-run
  is necessary, not sufficient. Run it on Thor and watch Step 2's exit before
  calling the tooling done. A standalone regression that reproduces the SIGPIPE
  mechanism (large producer piped to `grep -q` under pipefail, assert the wrong
  branch fires) lives at `scripts/sigpipe-pipefail-regression.sh` in this skill —
  run it to prove the capture-to-var idiom survives where the pipe fails.
- Keep the manual steps in DOCKER-BUILD.md as the reference the script
  automates; add a short "Quick deploy (side-load)" banner at the top pointing
  at the script. Don't delete the runbook — the script IS the runbook, executable.

Verification without a canonical suite: build throwaway repo fixtures under a
`mktemp -d` temp dir (a fake `sage.yaml` with distinct ns/name/version + a
matching job YAML + a mismatched one), run the script `--dry-run` against them,
and assert parsed tag / drift warning / `--submit` refusal on mismatch / exit
codes. Isolated fixtures prove the parsing generically (not just against the one
real repo). NOTE: the real docker/k3s/sesctl calls only run on Thor — from a dev
box only `--dry-run` + syntax (`bash -n`) are verifiable; say so explicitly
rather than claiming full verification.

## ECR catalog registration via API (the key discovery)

You do NOT need the portal UI to register a catalog version.

- `GET  https://ecr.sagecontinuum.org/api/apps/<ns>/<name>/<ver>` returns a
  full app record (fields: description, authors, inputs, source, metadata…).
- `GET  https://ecr.sagecontinuum.org/api/apps/<ns>/<name>` returns all
  registered versions (`data[].id`) — works anonymously if the app is
  public, which is how you confirm a version is registered + public.
- `POST https://ecr.sagecontinuum.org/api/submit` with header
  `Authorization: Sage <portal-token>` and a JSON body registers a version.
  Clone a known-good prior version's record, bump `version` and `source`.
  REQUIRED field: `description` (500 if missing).
  Returns 200 with the new record; returns 500 `App ... already exists.`
  if the version is already registered (treat as success / idempotent).

Auth header scheme is `Authorization: Sage <token>` (not Bearer/Token).

### FIRST-EVER version of a NEW app: clone-from-prior FAILS; use `pluginctl run` (VERIFIED sage-yolo2, H00F 2026-07-14)
`register-ecr-version.py` (and `deploy-sideload.sh`'s auto-detect) CLONE metadata
from an existing `/apps/<ns>/<name>/<from-version>` — so for a brand-NEW app name
with ZERO prior versions the register step has nothing to clone and dies ("no prior
catalog version found"). Two ways forward, in preference order:
1. **If you only need a real on-node run (dev/test/first-deploy): use
   `sudo pluginctl run` — it BYPASSES the ECR-catalog gate entirely.** No catalog
   record, no registration, no portal. This is the correct run mode for a new
   plugin until you actually want an SES cron. The image just needs to be
   side-loaded into k3s (build → `k3s ctr images import`). This is what shipped
   sage-yolo2 2.0.0 for its Stage-7 e2e — full producer→cache→consumer round-trip,
   frame-anchored counts confirmed in the data API, with NO ECR catalog record.
2. **If you need the SES path (cron, reboot-survival, scheduler):** the catalog
   DOES need a first record. Either register once via the portal UI, or POST a
   full record built from `sage.yaml` directly to `/api/submit` (all fields
   inline, `description` REQUIRED) instead of cloning. NOTE: writing a new catalog
   record is a real side-effecting action — get the user's explicit OK before
   POSTing (the registration POST was declined once this session; `pluginctl run`
   was the right call for a stopping point that didn't need SES).
Decision rule: **`pluginctl run` for run-it-now; ECR-catalog register only when
SES scheduling is actually required.** Don't register a catalog version just to
prove a plugin works — side-load-run proves it end-to-end without it.

## Pitfalls learned this session

- **Bare vs registry image name mismatch.** The old `pluginctl` workflow
  tagged images by bare name (e.g. `bioclip-species:0.3.0`), but the ECR
  app / registry name differs (`bioclip-species-classifier`). The sideload
  tag and job YAML image: MUST use the registry name, or the pod won't find
  the cached image.
- **Token write-scope confusion.** A Sage portal token that 401'd on an
  earlier `sesctl rm` was actually write-capable — the failure was a
  shell-quoting bug in how the token was passed, NOT a permission issue.
  The same token successfully did create/submit and ECR POST /submit. Don't
  assume read-only from one failed write; re-test with clean quoting.
- **EXPIRED token presents as misleading auth errors — refresh first.** Two
  distinct symptoms, same root cause (the stored token at `~/.sage-token`
  went stale): ECR API `GET /apps/<ns>/<name>/<ver>` returns
  `HTTP 401 {"error": "Token not found"}`, and (if the token has a trailing
  newline) `{"error": "Authorization failed (could not parse Authorization
  header)"}`. Before deep-diagnosing "is the app/version registered?" or
  "is my namespace wrong?", just RE-COPY the token from
  portal.sagecontinuum.org and overwrite the file:
  `printf '%s' '<token>' > ~/.sage-token` (printf, no trailing newline).
  A quick auth probe isolates token-vs-everything-else in one call:
  `curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Sage $TOKEN" \
    https://ecr.sagecontinuum.org/api/apps/<ns>/<name>/<ver>` — 200 = token
  good, 401 = refresh it. Always strip whitespace when reading the file
  (`read -r TOKEN < ~/.sage-token` strips the newline; piping `cat` keeps it).
- **Hermes redaction can mangle `$(cat token)` substitutions.** When a shell
  command contains a command-substitution that reads a secret, the agent
  harness may redact it to `***` and corrupt the command (syntax error, or a
  literal `***` passed as the token). Workaround that survives redaction:
  read the token on the NODE inside a `bash -s` heredoc with
  `read -r TOKEN < "$HOME/.sage-token"` (a plain redirect, not a
  substitution), then reference `"$TOKEN"`. Don't fight it with rephrasings.
- **Data API records key the job name under `meta.task`, NOT `meta.job`.**
  Recurring mis-scoped-filter trap: filtering/grouping query results on
  `meta["job"]` yields `job="?"` and ZERO matches, which looks exactly like
  "the deploy is broken / nothing is publishing" when the job is actually
  healthy. The records DO exist — you queried the wrong key. Group by
  `meta["task"]` (the job NAME, e.g. `"insect-bioclip"`) and read the version
  from the tail of `meta["plugin"]` (`registry.../<name>:<VERSION>`). Other
  meta keys present: camera, host, node, rank, vsn, zone. There is no
  `meta.job`. When a just-deployed plugin appears to publish nothing, re-run
  the query grouped by `meta.task` BEFORE concluding the pod is dead.
- **Verify a save-decoupled plugin on BOTH paths, and don't mistake a quiet
  scene for a broken deploy.** For the publish-always / save-on-match pattern
  (see references/publish-vs-save-decoupling.md), confirm two things
  separately: (1) NEGATIVE path — every cycle emits the heartbeat/summary +
  `plugin.duration.*` even with zero confident detections, and uploads stay at
  zero; (2) POSITIVE path — a real detection above the save threshold produces
  an `upload` record. The positive path often can't be forced on demand
  (e.g. a vision model pre-dawn sees nothing above 0.7; check the local clock
  before declaring failure) — set a data-API watcher and let daylight/activity
  produce it naturally rather than running an off-window GPU job. Telemetry
  (`plugin.duration.inference`) firing while the summary heartbeat is ABSENT is
  the classic signature of a heartbeat call gated behind `if detections:`.
- **Sideload is large + slow.** 28GB bioclip save|import runs several
  minutes; always background it with completion notification rather than
  blocking a foreground SSH call (60s window). Small CPU-only images (birdnet
  ~2.8GB) build+sideload in ~3-4 min total even with `--no-cache`
  re-downloading the model; the GPU/NVIDIA images (yolo ~5GB, bioclip ~28GB)
  are the slow ones.
- **One-shot pods are invisible between ticks.** `kubectl get pods -n ses`
  is usually empty; the pod fires for ~30-60s on the */10 tick then is GC'd.
  Verify via the data API or catch a pod with a watch loop.
- **birdnet runtime note:** logs `No node manifest found — geo-filtering
  disabled` means lat/lon auto-detect failed, so eBird seasonal filtering
  is off (still classifies, just against the global list). Follow-up item.
- **A plugin CANNOT learn its own VSN or GPS at runtime (as of 2026-07-06).**
  Verified four ways: pywaggle 0.56 has no gps/vsn/location/node API (source
  grep: zero hits); its docs expose only publish/subscribe/upload_file; a live
  `ses` plugin pod has ONLY `WAGGLE_PLUGIN_*` + `WAGGLE_SCOREBOARD` env and mounts
  ONLY `/run/waggle/{uploads,data-config.json}`; and the yolo/bioclip plugins
  don't self-identify at all. CRITICAL: `/etc/waggle/` (which holds
  `node-manifest-v2.json` with vsn/gps_lat/gps_lon, and `vsn`/`node-id` files) is
  a node-HOST path and is **NOT mounted into plugin pods** — reading it works only
  when you run the code directly on the node host (dev/spikes), which will MISLEAD
  you into thinking auto-resolve works. Inside a pod it returns nothing. The
  platform model is deliberate: **the plugin is node-agnostic; Beehive stamps
  `vsn`/`node` DOWNSTREAM via message routing.** PROVEN: an image-sampler2 upload
  whose filename used a placeholder vsn `NODE` came back from the data API with
  `meta.vsn=H00F, meta.node=00004cbb4701d16c` — attribution is correct regardless
  of what the plugin knows. So: do NOT block an upload on missing vsn/gps. If you
  need geo/vsn in the file itself, either pass it as an explicit arg, or fall back
  to a clearly-marked placeholder (vsn) and OMIT gps (never fabricate coordinates).
  The Sage CI team is adding runtime "GPS call" + "VSN call" APIs (~mid-2026);
  until then a placeholder is the correct interim.
- **EXCEPTION / UPDATE (verified W06C 2026-07-11): a GPS-EQUIPPED node DOES let a
  plugin self-locate at runtime — via the DATA PLANE, not env/manifest.** The
  "cannot learn GPS at runtime" rule above is about env vars + the in-pod manifest
  (both genuinely unavailable). But a node with a real GPS sensor (e.g. W06C's
  VK-162) runs a device plugin that PUBLISHES `sys.gps.lat` / `sys.gps.lon` to
  Beehive, and any plugin can `plugin.subscribe("sys.gps.lat","sys.gps.lon")` and
  read a live fix off the message bus. This is the ONE working runtime-location
  mechanism today. Our birdnet app.py implements it (`_coords_from_live_gps()`,
  gated behind the `--gps-subscribe` store_true flag; resolution order when
  `--lat/--lon` are unset = live sys.gps.* → manifest → env → else geo-filter off).
  HOW TO TELL A NODE HAS IT before deploying (data API, node-agnostic — no ssh):
  `search_measurements("gps|lat|lon", node_id=<VSN>, time_range="-2h")` and look
  for `sys.gps.lat/lon` updating, `sys.gps.mode`=3 (3D fix), `sys.gps.satellites`
  >=4, and `sys.sanity_status.wes_gps_server`=0 (healthy). If present → deploy the
  job with `--gps-subscribe` and NO hardcoded `--lat/--lon` (portable, self-locating,
  correct if the node moves). If ABSENT (fixed node like H00F publishes no
  sys.gps.*) → fall back to explicit `--lat/--lon` from the node-info GPS. So the
  per-node choice is: live-GPS subscribe where the stream exists, hardcoded coords
  where it doesn't — check the data plane first, don't assume.
  **BUT `--gps-subscribe` DOES NOT RELIABLY WORK AS SHIPPED (verified FAILED on
  W06C 2026-07-11) — do not assume the flag alone gives you geo-filtering.** The
  pod log showed `No node location available (live GPS / manifest / env all
  absent) — geo-filtering disabled`, i.e. BirdNET fell back to the GLOBAL species
  list, even though W06C's data plane was publishing a healthy `sys.gps.*` 3D fix.
  ROOT CAUSE: `_coords_from_live_gps()` opens a `plugin.subscribe(...)` with only a
  ~3-second timeout, but the node's GPS device plugin publishes `sys.gps.lat/lon`
  just once every ~2 MINUTES. The subscribe only receives messages emitted DURING
  its short window, so it misses the slow GPS heartbeat ~97% of the time and gives
  up. The subscribe isn't broken; the window is far too short for the publish
  cadence. IMPLICATIONS:
    - INTERIM for a FIXED GPS node: still pass explicit `--lat/--lon` (coords are
      stable; from node-info or the manifest) so geo-filtering is correct TODAY.
      `--gps-subscribe` is currently cosmetic on such nodes.
    - PROPER FIX (app.py change, not yet done): resolve live location by QUERYING
      the data API for the LAST `sys.gps.lat/lon` value
      (`POST data.sagecontinuum.org/api/v1/query {"start":"-15m","filter":{"vsn":
      <VSN>,"name":"sys.gps.lat"}}`) instead of a 3s in-pod subscribe — that reads
      the most-recent published fix instantly and robustly, and makes the flag work
      on mobile nodes too. (A much longer subscribe timeout, >2 min, would also
      catch it but wastes pod time each one-shot tick.)
    - HOW TO CATCH THIS: it's SILENT in the data plane — the plugin still publishes
      detections + heartbeat, just against the wrong (global) species list. The
      ONLY proof is the pod's STARTUP LOG. Catch a one-shot pod live with a watch
      loop on the node (`ssh waggle@waggle-dev-node-<vsn>` →
      `for i in $(seq 1 60); do pod=$(sudo kubectl get pods -n ses|grep <name>|
      tail -1|awk '{print $1}'); sudo kubectl logs -n ses $pod 2>/dev/null|grep -i
      location && break; sleep 3; done`) and read whether it says
      "Node location from live sys.gps.* stream" (WORKED) or "No node location
      available ... geo-filtering disabled" (FELL BACK — filter is off).
- **CPU-only plugins need NO side-load — they PULL from ECR (don't run this whole
  pipeline for them).** This entire file is the GPU/NVIDIA workaround. A CPU plugin
  (birdnet-species: python:3.12-slim + TFLite, no CUDA) builds cleanly in ECR, so
  its image is a normal pullable registry manifest — deploying it to a new node is
  just `sesctl create/submit` with the existing `beckman/<name>:<ver>` image; no
  native build, no `k3s ctr import`, no register step. CONFIRM pull-ability in one
  call before deploying: `GET ecr.sagecontinuum.org/api/apps/<ns>/<name>` lists the
  registered versions, and an HTTP 200 on `/apps/<ns>/<name>/<ver>` means the
  catalog record exists. Reserve build→import→register for NVIDIA-base plugins only.
- **`sesctl stat` shows only YOUR OWN jobs, not other users'.** To replace another
  user's job (e.g. take over a node from a collaborator), you CANNOT see their
  numeric job ID with your token — get the ID from them or have them suspend/remove
  it. You can still SEE what they're running via the data plane
  (`search_measurements`/`get_node_all_data` on the node) to read their plugin,
  cadence, and capture duration off `plugin.duration.input`/`loadmodel` timestamps
  — enough to match their sampling/inference rate in your replacement job.
  You can also read the job's owner + metadata with `sesctl stat -j <id>` even
  when it's not yours (read is allowed; write is not). And you can SEE their pod
  on the node itself via the waggle gateway: `ssh waggle@waggle-dev-node-<vsn>`
  then `sudo kubectl get pods -A` lists `ses/<plugin>-<jobid>` regardless of
  submitter — that's how you recover the numeric job ID without asking.
  DEAD-END — do NOT burn turns on it (verified W06C 2026-07-11): you CANNOT stop
  another user's SES job by any flag combination. `sesctl rm -s <id>` → `400 user
  "X" is not the owner of job "<id>"`; adding `--override --force` → `400 User X
  does not have permission to override to the job` (the override flag itself needs
  an elevated/admin grant a normal user token lacks). Killing the pod on the node
  with `kubectl delete pod` is also futile — the SES cron respawns a fresh pod on
  the next tick (whack-a-mole). The ONLY ways to stop it: the job's OWNER runs
  `rm -s`/`rm`, or a Sage ADMIN does it. Even with verbal permission from the
  owner, the clean path is to have THEM suspend/remove it, then you launch yours.
- **Side-loading via `pluginctl run` (no ECR, no registry) for a quick real
  round-trip.** `pluginctl build`'s push to the node-local registry
  (`NODE_CONTROL_PLANE_IP:5000`) fails when `lan0` is down. Sidestep it entirely: build with
  podman, tag as `docker.io/library/<name>:<ver>`, `podman save | sudo k3s ctr
  images import -`, then `sudo pluginctl run --kubeconfig /etc/rancher/k3s/k3s.yaml
  <img> -- <args>`. The beckman kubeconfig is namespace-scoped and CANNOT create
  pods; the k3s admin config (`/etc/rancher/k3s/k3s.yaml`, root) can — pass it via
  `--kubeconfig`. Inject camera creds with `--env-from <file>` (env, never argv).
  This gives a full Beehive round-trip (real WES pod, real upload plumbing) without
  ECR registration or a registry push. One-shot pods exit after the upload (that's
  correct); verify via the data API, not kubectl.
- **ECR/Jenkins buildkit `/proc/acpi` runc failure is a builder bug, not yours.**
  Every `RUN` step (apt-get, pip, anything) fails with
  `runc run failed: ... can't mask dir "/proc/acpi": ... invalid argument`. It is
  arch-independent (both arm64 and amd64 hit it) and unfixable from the Dockerfile.
  ROOT CAUSE (confirmed 2026-07-07): the runc masked-paths hardening from
  **CVE-2025-31133 / -52881 / -52565** (pub 2025-11-05). The ECR buildkitd host
  runs a patched runc (>=1.2.8/1.3.3/1.4.0-rc.3) whose stricter `/proc/acpi`
  tmpfs-mask now returns `invalid argument` on that host's kernel. Fixable ONLY on
  the Sage side (builder kernel upgrade, runc pin, or relax buildkitd masked-paths).
  Filed: waggle-edge-stack#110. **DEAD-END — do NOT re-attempt:** swapping the base
  image does NOT help (proven: v0.5.0 on `waggle/plugin-base` failed on `pip`, then
  v0.5.1 on `python:3.12-slim` failed IDENTICALLY on `pip`, both arches — FROM/
  WORKDIR/COPY succeed, the FIRST `RUN` always dies at container init regardless of
  base). Irrefutable proof for the issue: register Sage's OWN reference plugin
  `waggle-sensor/plugin-imagesampler` (unchanged, built cleanly ~1yr ago) fresh in
  ECR and it fails at its first `RUN` (apt-get) with the same error — kills any
  "your plugin's fault" objection. Build natively with podman on the node instead
  (podman's `RUN` works fine). Note `waggle/plugin-base:1.1.1-base` is Python 3.8.5
  + pywaggle 0.40.7 (too old — no `upload_file`); prefer `python:3.12-slim` for
  CPU-only plugins (modern, smaller, no OpenCV/numpy chain if you only use core
  `waggle.plugin.Plugin`; `pywaggle` without `[vision]` is enough — no cv2). podman
  needs the FULLY-QUALIFIED base name (`docker.io/...`).
- **`git pull --ff-only` on the node can be blocked by a benign file-MODE
  change.** Step 1's `git pull` aborted with `Your local changes to the
  following files would be overwritten by merge` for a test helper — but the
  only diff was a mode change (`old mode 100644 / new mode 100755`), made
  INDEPENDENTLY on both the node and the committing machine (same chmod, no
  content difference). Diagnose with `git diff <file>` (shows only the mode
  lines) and `git diff HEAD origin/main -- <file>`; if both are mode-only,
  discard the node-side change with `git checkout -- <file>` and re-run the
  ff-only pull. Use gentle `git fetch` + `git pull --ff-only` for node sync —
  NOT `git reset --hard` (a hard reset over SSH can trip the agent's
  security-approval gate and also discards any genuine node-side edits).
  Untracked artifacts (e.g. test `.wav`/`.mp3` files) don't block a pull.

## Diagnosing a one-shot pod that "runs" in SES but publishes nothing

Symptom: `sesctl stat -j <id>` shows Running, pod events show the container
starting every */10 tick and the image pulling fine ("already present on
machine"), but the data API returns ZERO records over the last hours.

Key diagnostic signal: **how long the pod lives.** Catch it with a watch
loop and time it. A heavy-model plugin (e.g. BioCLIP 2.5 ViT-H/14, ~28GB)
physically CANNOT capture + load model + classify + publish in a few
seconds — model load alone takes longer. So a pod that is GC'd in under
~4-5 seconds is **crashing at startup**, before it ever loads the model.
That points at an early-execution failure: an import error, a syntax error,
or an arg-parse failure — NOT a camera/model/runtime issue.

Common trigger: a recent code edit (e.g. an annotation refactor) that
introduced an import-time or parse-time error. A plugin that published fine
right after cutover and then went silent is suspicious for an
intermittent/state-dependent path, but a sub-5s exit on EVERY tick is a
hard startup crash.

Safe triage (read-only, no scheduler/job/node-state change — just runs the
image locally and exits): exercise imports + arg parsing without needing a
camera or GPU:

```bash
sudo docker run --rm --entrypoint python3 \
  registry.sagecontinuum.org/<ns>/<name>:<ver> /app/app.py --help
```

- Prints help text -> imports/parsing are fine; the crash is runtime
  (camera reachability, model load, OOM) — look at full pod logs instead.
- Throws a traceback -> that's the bug, in import or top-level code.

If the bad version replaced a known-good one, the fast recovery is to
revert the offending function to the last-good version (which ran for
hours), rebuild + sideload + re-register + resubmit, then re-apply the
intended change minimally and re-test. Keep the previous job SUSPENDED (not
removed) during a version cutover so it's a one-command rollback point;
only `sesctl rm <old-id>` once the new version is confirmed publishing.

Note: catching a sub-5s one-shot pod's logs live is racy — the pod often
vanishes before `kubectl logs` runs. The `docker run --help` probe above is
more reliable for startup crashes than chasing the live pod.

## Continuous vs one-shot: sampling cadence MUST match subject behavior

This caused a real ~2-day outage. A camera plugin was moved from a
continuous pod (`--continuous Y --interval 60`, ~1440 frames/day) to a
`*/10` one-shot SES cron (~144 frames/day). Detections of the target
(hummingbirds) collapsed from ~15/day to ~0, and a downstream Slack watcher
went silent. The plugin and model were fine — the **sampling rate dropped
~10x**, and the subject (a hummingbird visiting a feeder for a few seconds)
was almost never in-frame at the 10-minute marks.

Decision rule for SES job mode:

- **Continuous** (`--continuous Y --interval <s>`, science rule
  `schedule(<plugin>): True`): pod stays running and samples every
  `<interval>` seconds; holds the GPU. Use for **fast / intermittent
  subjects** — birds, traffic, people, anything in-frame only briefly.
- **One-shot cron** (`--continuous N`, science rule
  `schedule(<plugin>): cronjob(<plugin>, '*/10 * * * *')`): one capture per
  tick, pod exits and frees the GPU between ticks. Use for **slow-changing
  scenes** — clouds, snow depth, parking occupancy, vegetation, water level.

Rule of thumb: if the subject appears briefly and unpredictably, use
continuous; if the scene changes slowly, one-shot is cheaper and fine. Each
one-shot tick reloads the model (~5GB YOLO, ~28GB BioCLIP), so for sub-2-min
sampling continuous is also more efficient — don't just crank the cron rate.

Important nuance: "scheduler-managed continuous" is NOT the bad old
hand-deployed `pluginctl` pod. A continuous plugin under SES still survives
reboots and is visible to the scheduler — you get reboot-survival AND the
high sample rate. Don't frame continuous as deprecated; frame it as a mode
choice. Audio plugins (e.g. birdnet capturing 30s per run) are less
sensitive to the gap because each run integrates over a window.

Diagnosing this class of regression: query the data API for ticks/day over
the days around the change (e.g. `env.count.total` count per day). A 10x
drop in TICK rate (not in detection rate) localizes the cause to sampling
cadence, not detection code. Confirm the subject-specific topic
(`env.count.bird`) tracks the tick collapse.

When deploying a camera plugin for a fast subject, ship BOTH job files so
students/operators can choose: `jobs/<cam>-h00f.yaml` (continuous, default)
and `jobs/<cam>-h00f-oneshot.yaml` (one-shot alternative), and put a
continuous-vs-one-shot decision table in DOCKER-BUILD.md. To switch a
running job between modes: `sesctl ... rm -s <id>` then `rm <id>`, then
create + submit the other file.

## Systemic fix to request from the ECR/cyberinfra team

The sideload+API-register path is manual and per-node. Durable fixes:
(a) grant push/write access to `registry.sagecontinuum.org/<ns>/` for a
portal token so `docker push` works after a native Thor build; or
(b) add a native arm64 build node to the Jenkins ECR pipeline so the portal
"Register and Build" path works without QEMU. Either unblocks every
Thor-targeted NVIDIA plugin and removes the manual steps.

### Documenting the workaround as an issue-ready section (do this)

When a platform workaround like sideloading is something the upstream team
should eventually FIX, write its documentation as a SELF-CONTAINED section the
user can lift verbatim into a GitHub issue — don't scatter it through a
deploy guide that assumes the rest of the doc's context. Proven shape (Pete
used this 2026-06-24: a standalone "Sideloading Builds" heading in
birdnet/DEPLOY-AND-RUN.md, explicitly flagged "intended to be lifted into a
GitHub issue"):
1. **What** the workaround is (one-paragraph definition + the one-liner command).
2. **Why** it's needed — the concrete blockers with exact error signatures
   (here: QEMU `signal 6 / exit 134` on arm64 NVIDIA base, and read-only token
   `denied: requested access to the resource is denied`).
3. **How** to use it (full procedure, copy-pasteable).
4. **Limitations/caveats** (per-node, manual, not reproducible, disk).
5. **The durable fix** as explicit options (a)/(b) for the team to choose.
Cross-link the step-by-step version (e.g. DOCKER-BUILD.md) so the issue stays
high-level while the runbook lives in the repo. This makes the doc do
double-duty: onboarding runbook AND escalation artifact.
