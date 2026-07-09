# ECR catalog registration via API + Thor arm64 deploy (no portal, no push)

Session-proven (2026-06-21) end-to-end path for deploying an arm64 plugin
to a Thor node when (a) the ECR portal build crashes under QEMU and (b) you
have no Docker-registry push scope. Both blockers are bypassed.

## The core insight: SES validates against the CATALOG, not the registry

`sesctl submit` checks whether the job's `image:` exists as a record in the
ECR **app catalog** (ecr.sagecontinuum.org/api), NOT whether the image is
pullable from registry.sagecontinuum.org and NOT whether it's in the node's
k3s containerd. So the two concerns are fully separable:

- **Catalog record** → satisfies `sesctl submit` validation. Create via API.
- **Actual image bytes** → served by the local **sideload** because SES
  pods run with `imagePullPolicy: IfNotPresent` ("already present on
  machine" in pod events confirms the local copy was used).

If the catalog lacks your exact version you get:
`[registry.sagecontinuum.org/<ns>/<name>:<ver> does not exist in ECR]`

## ECR API contract (discovered this session)

- Base: `https://ecr.sagecontinuum.org/api`
- Auth header: `Authorization: Sage <portal-token>`  (NOT Bearer/Token)
- `GET /apps/<ns>/<name>`            → public catalog list: `{"data":[{id,...}]}`
- `GET /apps/<ns>/<name>/<version>`  → one full version record (auth'd)
- `POST /submit`                     → register a version. Body = full app
  metadata JSON. **Required field: `description`** (500 "Required field
  description is missing" otherwise). Re-submitting an existing version →
  500 "App ... already exists" (treat as idempotent success).
- A version visible to an anonymous `GET /apps/<ns>/<name>` == it is public.
  If not public, SES returns `registry does not exist in ECR`.

Easiest: clone a prior version's record, bump `version` + `source.url`/branch,
POST it. See `scripts/register-ecr-version.py` (tested, idempotent).

## Full deploy sequence (one uniform path for ALL Thor plugins)

1. Build natively ON Thor (arm64, no QEMU), tagged with the FULL registry
   path so it matches the job YAML `image:` exactly:
   `sudo docker build -t registry.sagecontinuum.org/<ns>/<name>:<ver> .`
2. Sideload into k3s containerd (large; run in background, ~1 min/GB):
   `sudo docker save registry.sagecontinuum.org/<ns>/<name>:<ver> | sudo k3s ctr images import -`
   Verify: `sudo k3s ctr images ls | grep <name>` → look for
   `io.cri-containerd.image=managed` (that label = k8s/SES can see it).
3. Register the catalog version via API: `scripts/register-ecr-version.py`.
4. `sesctl ... create -f jobs/<job>.yaml` → returns numeric job id.
5. `sesctl ... submit -j <id>` → should now pass validation.
6. Verify via DATA API, not kubectl (one-shot pods GC within ~30-40s, so
   `kubectl logs` usually races to "pod not found"). Proof it's the SES job
   and not a leftover hand-deployed pod is in record metadata:
   `"job":"<name>-<id>"` and `"plugin":"registry.sagecontinuum.org/<ns>/..."`.

## Version cutover (redeploying a new image tag to a live job)

A running job is pinned to its image tag at submit time; bumping the plugin
version means a NEW job, not an in-place update. The proven cycle:
1. Suspend the old job:  `sesctl ... rm -s <old-id>`  → state "Suspended"
2. Remove it:            `sesctl ... rm <old-id>`     → state "Removed"
   (must suspend before remove if it's Running)
3. `create -f jobs/<job>.yaml` → returns a NEW numeric id (ids are not reused;
   e.g. 5647→5649→5651 across this session's bioclip redeploys).
4. `submit -j <new-id>`.
Leaving the old job Suspended (skip step 2) is a valid rollback point; remove
it once the new version is confirmed.

CRITICAL verification gotcha: `sesctl stat -j <id>` showing **"Running" is a
CLOUD-level claim, not proof a pod exists.** Always cross-check with the actual
pod list (`kubectl get pods -n ses`) AND the data API. This session hit a case
where SES said job 5651 was "Running" but NO pod was ever created (single-GPU
contention — see scheduling-continuous-vs-oneshot-and-gpu-contention.md). "0
records in the data API for the new plugin tag" is the fastest liveness probe.

A Sage portal access token has BOTH read and write/scheduling scope. An
earlier apparent 401 on `sesctl rm` was a SHELL-QUOTING bug (token mangled
when interpolated as `TOKEN=*** SRV=...` on one SSH line), NOT a permission
problem. Pass the token inline and unquoted-but-clean; don't assume a 401
means read-only — re-test with a known-good invocation first.

## Why the portal build fails (context for the workaround)

ECR/Jenkins builds run on x86_64 and cross-build linux/arm64 under QEMU.
The NVIDIA base (nvcr.io/nvidia/pytorch:25.08-py3) contains aarch64 binaries
QEMU can't emulate; `pip install`/`import torch` crashes with
`qemu: uncaught target signal 6 (Aborted) - core dumped`, build exit 134.
Removing `linux/amd64` does NOT help — the crash is arm64-under-QEMU itself.
CPU-only plugins on `python:3.12-slim` (e.g. birdnet) do NOT hit this, but
keep them on the same sideload path so students learn ONE procedure.

## Systemic fix to request from the ECR/cyberinfra team

The sideload is manual per-node. Durable fix is either (a) registry
push/write access for the namespace, or (b) a native arm64 build node in the
Jenkins ECR pipeline. Either removes the manual sideload entirely.

## One-shot vs continuous pods

SES cron jobs (`cronjob('name','*/10 * * * *')`) fire one-shot pods that
exit after publishing — invisible between ticks, no 24/7 GPU/RAM hold,
survive reboot, scheduler-managed. Prefer this over hand-deployed
`pluginctl deploy --continuous Y` pods (live in `default` ns, hold
resources, die on reboot, invisible to scheduler). Caveat: heavy models
(e.g. BioCLIP ViT-H/14) reload each cycle — fine at */10, measure cold-start
before tightening cadence.
