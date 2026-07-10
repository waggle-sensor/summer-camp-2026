# Deploying ARM64 plugins to Thor nodes (the working pipeline)

When the ECR portal build fails for a Thor/arm64 plugin, this is the
end-to-end path that actually works. Proven on H00F (Jetson Thor) for
yolo-object-counter, bioclip-species-classifier, and birdnet-species.

## The two blockers this solves

1. **ECR portal build crashes on arm64 NVIDIA images.** The ECR/Jenkins
   build pipeline runs on x86_64 and cross-builds `linux/arm64` under QEMU
   emulation. The NVIDIA base image (`nvcr.io/nvidia/pytorch:25.08-py3`)
   contains aarch64 binaries QEMU cannot emulate; the `pip install` /
   `import torch` step aborts with:
   `qemu: uncaught target signal 6 (Aborted) - core dumped`, build exit 134.
   Removing `linux/amd64` from sage.yaml does NOT help — the crash is in the
   arm64-under-QEMU path itself, not the amd64 build. (BirdNET on
   `python:3.12-slim` does NOT hit this — CPU-only, native wheels — but we
   keep all plugins on one deploy path for consistency.)

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

## The pipeline (run on the Thor node, e.g. ssh beckman@node-H00F.sage)

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
- **Side-loading via `pluginctl run` (no ECR, no registry) for a quick real
  round-trip.** `pluginctl build`'s push to the node-local registry
  (`10.31.81.1:5000`) fails when `lan0` is down. Sidestep it entirely: build with
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
