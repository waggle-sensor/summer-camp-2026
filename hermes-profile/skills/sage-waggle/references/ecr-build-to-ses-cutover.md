# ECR "Register and Build" → official SES job (cutover from side-load)

As of 2026-07-10 the Thor/arm64 ECR buildkit bug (`/proc/acpi` runc error on
every `RUN` step, was Infra #2) is **FIXED by the CI team**. Consequence: the
side-load era is over for CPU-base plugins — the standard ECR pipeline builds them
natively. Treat ECR "Register and Build" as the PRIMARY deploy path; side-loading
(`pluginctl-sideload-and-node-build.md`) is now a historical/offline fallback.

## Verified end-to-end (birdnet-species 0.2.1)

birdnet (`FROM python:3.12-slim`, CPU-only tflite — no CUDA/QEMU path) built
cleanly through ECR: three `RUN` steps (apt, pip, build-time model pre-download) —
exactly the path that previously died — completed. This build IS the verification
of record that the buildkit fix works.

## Tagging so ECR builds the right commit

ECR builds a version whose number matches `sage.yaml`'s `version:`. Push an
annotated git tag on the clean, in-sync HEAD:

    git tag -a v0.2.1 -m "birdnet-species 0.2.1"   # matches sage.yaml version
    git push origin v0.2.1
    git ls-remote --tags origin | grep v0.2.1      # verify tag + peeled ^{} commit

Repo must be public/anon-cloneable (`git ls-remote <https-url> main` succeeds) or
ECR can't fetch it. sage.yaml authors → work email (public); never the private one.

## Triggering the ECR build by API (no portal UI) — TWO steps, don't confuse them

Registering a catalog version and BUILDING the image are SEPARATE actions; doing
only the first leaves you with a catalog record but NO pullable image (verified
birdnet 0.3.0, 2026-07-11 — the pod would then sit `Pulling` / ImagePullBackOff).

1. REGISTER catalog metadata: `scripts/register-ecr-version.py` (POST /api/submit).
   This ONLY writes the catalog record — it does NOT build. `/api/apps/<ns>/<name>/<ver>`
   returns the record but `build keys: []` and the registry has no manifest yet.
2. TRIGGER the Jenkins build: `POST https://ecr.sagecontinuum.org/api/builds/<ns>/<name>/<ver>`
   with header `Authorization: Sage <token>` and body `{}` → returns
   `{"build_number": N}`. (NOTE the path shape: `/api/builds/<ns>/<name>/<ver>`
   works; `/api/apps/<ns>/<name>/<ver>/builds` returns 404 "Resource not
   supported" — the builds collection is top-level, not nested under apps.)
   Poll status: `GET /api/builds/<ns>/<name>/<ver>` returns the Jenkins WorkflowRun
   JSON — `result` is null while building, then `SUCCESS`/`FAILURE`; `building`
   is true/false. A CPU plugin builds in a few minutes.

This is the full portal-free path: `register-ecr-version.py` → `POST /api/builds/...`
→ MAKE PUBLIC (step 3, below) → poll → `sesctl create/submit`. No web UI. (For a
NVIDIA/CUDA plugin the build will still FAIL at the QEMU step — Infra #3 — so this
API path only completes for CPU-base plugins; see the GPU section below.)

3. MAKE THE NEW VERSION PUBLIC — required, and EASY TO MISS because it fails
   node-specifically. A freshly-built ECR image is PRIVATE by default. A node whose
   k3s has cached registry creds (e.g. W06C) pulls it fine, so the first cutover
   looks fully working — but a node pulling anonymously (e.g. H00F) gets, in the
   pod events: `Failed to pull ... insufficient_scope: authorization failed` /
   `ErrImagePull` → `ImagePullBackOff`. Verified birdnet 0.3.0, 2026-07-11: W06C
   ran 0.3.0 fine while H00F's pod sat in ImagePullBackOff on the SAME tag purely
   because the app wasn't public. Grant public read on the REPOSITORY (covers all
   versions), via API:
     curl -s -X PUT -H "Authorization: Sage $TOKEN" -H 'Content-Type: application/json' \
       https://ecr.sagecontinuum.org/api/permissions/<ns>/<name> \
       -d '{"operation":"add","granteeType":"GROUP","grantee":"AllUsers","permission":"READ"}'
   Verify: `GET /api/permissions/<ns>/<name>` should list an `AllUsers GROUP READ`
   entry alongside the owner's `FULL_CONTROL`. (The portal "make public" toggle does
   the same thing.) NOTE: the ACL change may not instantly propagate to already-
   backed-off pods — ImagePullBackOff retries with exponential backoff, so it can be
   minutes before SES re-attempts. To confirm/expedite: on the node, force a pull
   with `sudo k3s ctr images pull registry.sagecontinuum.org/<ns>/<name>:<ver>` — a
   clean pull (exit 0, image shows `io.cri-containerd.image=managed`) proves it's
   now public AND pre-caches it so the next SES tick uses it immediately
   (imagePullPolicy=IfNotPresent). Distinguish the two pull-failure modes:
   `insufficient_scope`/`ErrImagePull` = PRIVATE (fix: make public); a plain
   `Pulling image ...` with no error that just takes minutes = slow first pull (fine,
   wait). Both look like a hang; the pod EVENTS tell them apart.

FIRST-PULL LATENCY on the node is real and looks like a hang but isn't: after an
ECR build succeeds, the FIRST SES tick on a node that has never pulled that tag
can sit `PodInitializing` / `Pulling` for SEVERAL MINUTES (verified ~5 min for
birdnet 0.3.0 on W06C's Raspberry-Pi compute node — slow link/disk). Check
`kubectl describe pod` events: a `Pulling image ...` event with NO error means
it's just slow, not broken (vs `ErrImagePull`/`ImagePullBackOff` = real problem).
The image caches after the first pull, so subsequent ticks are fast. Don't
conclude the build/image is bad from a slow first pull — read the events.

## Cutover: replacing a side-loaded/old SES job with the official one

The "side-loaded" instance is often ALREADY an SES job (submitted back when the
image was side-loaded into k3s), NOT a manual `pluginctl` deploy. Check both:
`sudo pluginctl ls` (manual) vs `sesctl ... stat` (scheduled). If it's an SES job,
retire it via sesctl, not pluginctl.

sesctl runs ON the node (H00F), needs `--server https://es.sagecontinuum.org
--token <SES_USER_TOKEN>` (token is NOT in the node's non-interactive env — ask
Pete; never guess). Flags (this version, differ from web docs):
  - `create -f jobs/<file>.yaml`   → returns `{"job_id":"NNNN","state":"Created"}`
  - `submit -j <numeric-id>`        → activates (job ID, NOT name)
  - `rm -s <id>`                    → SUSPEND
  - `rm <id>`                       → REMOVE (positional ID; must suspend first if Running)

STOPPING SOMEONE ELSE'S JOB (cross-owner override). `sesctl rm <id>` on a job you
don't own normally returns `400 "user \"X\" is not the owner of job \"NNNN\""`, and
plain `rm -s --override --force` returned `400 "User X does not have permission to
override"`. BUT there IS a working form (confirmed by Pete, 2026-07-12) — run it
FROM a Sage node (e.g. H00F) with your own token; the platform grants the override
when invoked this way:
    sesctl --token <your_token> --server https://es.sagecontinuum.org/ rm <id> --override --suspend
i.e. `rm <id> --override --suspend` (suspend, reversible) — and `--override` without
`--suspend` to remove. Prefer `--suspend` first (reversible) on someone else's job,
verify, then remove. Only do this with the owner's explicit permission (Pete
coordinates with the other user, e.g. gojian). The earlier "override denied" was a
flag/scope quirk, NOT an absolute block — this exact invocation works from a node.

Cutover sequence (zero-downtime, safe):
1. `create -f jobs/...yaml` then `submit -j <new>` → new job Running.
2. Discover the duplicate: `sesctl stat | grep <name>` — same name/args → dup.
3. SUSPEND the old (`rm -s <old>`) immediately — stops double-hitting the
   camera/mic. Do NOT remove yet.
4. VERIFY the new job is actually publishing before removing the old one. The
   handoff completes at the NEXT cron tick, not instantly — old job's last cycle
   may still land right after you suspend it.
5. Once verified, `rm <old>` (irreversible on a long-running job — get user's
   explicit go before this step).

## Verifying WHICH job publishes (the decisive check)

Every data record carries `meta.job` = `<plugin>-<jobid>` and `meta.plugin` =
the image tag. Use the direct data API (more reliable than the MCP NL query,
which drifts to other plugins on broad queries):

    curl -s -X POST https://data.sagecontinuum.org/api/v1/query \
      -H 'Content-Type: application/json' \
      -d '{"start":"-15m","filter":{"vsn":"H00F","name":"env.detection.audio.summary"}}'

Then parse `meta.job` to confirm only the new job ID appears. `total_detections:0`
records are the healthy heartbeat (published every cycle since birdnet 0.2.0), so
liveness is confirmable even with zero detections.

## GPU / NVIDIA-base plugins: ECR STILL FAILS (blocker #3 confirmed OPEN 2026-07-10)

CPU-base plugins (birdnet, `python:3.12-slim`) only ever hit the `/proc/acpi`
buildkit bug — fixed → they build. But NVIDIA/CUDA-base plugins
(yolo `FROM nvcr.io/nvidia/pytorch`, bioclip) had TWO independent blockers:
  1. `/proc/acpi` runc bug (affected everything) — fixed by CI.
  2. QEMU cross-build crash: ECR/Jenkins runs on x86 and cross-builds arm64 under
     QEMU emulation, which SIGABRTs (`signal 6`, exit 134) on the aarch64 CUDA
     base. SEPARATE issue (Infra #3); needs a **native arm64 build node** to fix.

VERIFIED OUTCOME (do not re-litigate): #3 is **STILL OPEN**. yolo v0.3.1 was
pushed + tagged + built in ECR on 2026-07-10 and FAILED at exactly the QEMU step
(`qemu: uncaught target signal 6 (Aborted)` / exit 134 during `pip`), with the
Jenkins log showing `buildctl ... --opt platform=linux/arm64` — i.e. still
cross-emulating, no native builder. So GPU/NVIDIA plugins continue to require
native-Thor-build + k3s side-load (`thor-arm64-deploy-pipeline.md`).

HARD LESSON — a USER BELIEF is NOT proof; wait for the build:
In this session the user asserted "CI added a native arm64 builder — proceed
treating ECR as the working path for yolo." I did, rewrote all of yolo's docs
ECR-primary, pushed+tagged — and the build failed, forcing a full revert. The
birdnet ECR success (CPU base) does NOT generalize to GPU bases. RULE: never
promote ECR to the primary documented path for an NVIDIA/CUDA-base plugin until
an actual ECR build of a NVIDIA-base plugin has SUCCEEDED. If asked to proceed on
a belief, you may push+tag to TEST the build, but keep docs describing side-load
as the working path until the build proves otherwise — writing "ECR is primary"
into docs first means reverting them when it fails. Check base image with
`grep '^FROM' Dockerfile`; `nvcr.io/nvidia/...` or CUDA → #3 applies.

Silver lining when a build fails: a fresh dated Jenkins failure log is a strong
escalation artifact for Infra #3 — attach it to the issue/email rather than the
theoretical writeup.

## Namespace + version consistency sweep (do this on every doc refresh)

Old docs drift: yolo's docs/job-YAMLs referenced `flint-pete/` AND `waggle/`
namespaces at stale tags (`0.2.0`) while the actually-built/running image was
`beckman/...:0.3.0`. `sage.yaml`'s `namespace:` field drives where ECR PUBLISHES,
so it must match reality. Determine the TRUE namespace from live data, not the
docs: query `meta.plugin` from the data API for the running plugin —
    curl ... -d '{"start":"-2h","filter":{"vsn":"H00F","name":"env.count.total"}}'
    → meta.plugin = registry.sagecontinuum.org/beckman/yolo-object-counter:0.3.0
Then normalize EVERY ref repo-wide (sage.yaml namespace, all *.md image tags, all
jobs/*.yaml `image:` + comments) to `<truens>/<name>:<newver>`. A regex sweep +
a temp `hermes-verify-*` script that asserts all `registry.../…:tag` matches the
sage.yaml namespace+version catches the drift. Version bump for a docs/metadata-
only change is a PATCH (e.g. 0.3.0→0.3.1), no plugin code touched.

WATCH the test harness too: `tests/run-tests.sh` had `birdnet-species:0.1.1`
hardcoded in 3 spots (image check, banner, `docker run`), so `make test` silently
built/ran a STALE tag — it passed only because an old 0.1.1 image lingered
locally, masking that it never exercised the new build. A version bump exposes
this. Fix: derive the tag from the Makefile once
(`VERSION="$(sed -nE 's/^VERSION[[:space:]]*:=[[:space:]]*([0-9.]+).*/\1/p' Makefile|head -1)"; IMAGE="<name>:${VERSION:-latest}"`)
and reference `$IMAGE` everywhere — never hardcode the tag in a test script, or it
drifts from what the Makefile builds.

## Doc hygiene after a cutover

Deploy docs written in the side-load era go stale. Refresh pattern that worked:
make ECR the primary section, demote side-loading into a collapsed
`<details>` "historical fallback" block (don't delete — offline bring-up still
uses it), add a dated status banner, and bump ALL stale image tags to the new
version across every doc (DEPLOY-AND-RUN, DOCKER-BUILD, DGX-TESTING). Leave the
CHANGELOG's version history intact (it's accurate historical record). Keep
correct "does not exist in ECR" explanations — that's still what SES returns for
an unbuilt/private app, not a stale claim.
