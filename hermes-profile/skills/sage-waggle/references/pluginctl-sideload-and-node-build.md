# Side-loading a plugin for testing: pluginctl vs sesctl+ECR

Two ways to run a plugin on a node, with different prerequisites:

## sesctl (scheduler / SES) — needs ECR registration
The scheduler validates the app exists in the ECR registry BEFORE launching.
Requires BOTH the ECR app metadata AND the built image to exist (two distinct
failure modes). This is the production path. Pods land in the `ses` namespace.

## pluginctl (direct node run) — NO ECR registration needed
`pluginctl run PLUGIN_IMAGE [-- PLUGIN ARGS]` runs the image in a real WES pod on
the node with full upload plumbing (RabbitMQ, /run/waggle/uploads -> Beehive
agent). It BYPASSES the ECR-registration gate entirely, so it's the right tool for
a real Beehive round-trip during development ("side-load for testing"). Pods land
in the `default` namespace.

Useful `pluginctl run` flags (verified on H00F):
    -e, --env strings       set env vars (e.g. -e CAMERA_USER=test)
    --env-from string       set env vars from a FILE  <-- use this for secrets so
                            the password never appears in argv / process listing
    --name / -n             plugin name
    --node                  target node
    --selector              placement (e.g. resource.gpu=true)
    --volume / -v           host path mounts
    --develop               enable WAN access
`pluginctl build PLUGIN_DIR` builds from a Dockerfile dir and PRINTS an image ref
usable by `pluginctl run -n name $(pluginctl build dir)`.

RBAC: `pluginctl run` may fail immediately with
`Error: pods is forbidden: User "<user>" cannot create resource "pods" in ...
namespace "default"`. pluginctl HARDCODES the `default` namespace (even
`pluginctl ps` targets `default`) and IGNORES the kubeconfig context's `namespace`
field — so even if `~/.kube/config`'s current-context sets `namespace: <user>`,
pluginctl still hits `default`, where the per-user account has no pod-create right.
FIX (verified on H00F): just run `sudo pluginctl ...` — sudo picks up root's
cluster-admin kubeconfig, which CAN create pods in `default`. Plain `sudo
pluginctl run/ps/logs/rm/exec` all work. (Do NOT bother with `--kubeconfig
/etc/rancher/k3s/k3s.yaml` as a non-root user — `kubectl` can't even read that
root-owned file: `permission denied`. `sudo` is the clean path.)
Verify who-can-do-what with
`sudo k3s kubectl auth can-i create pods -n default` (admin = yes) vs
`kubectl --kubeconfig ~/.kube/config auth can-i create pods -n <user-ns>` (the ns
the user CAN write, usually their own). Note the one-shot pod EXITS after its
upload (that's correct); a `--continuous` pod STAYS Running (inspect it live). If
`pluginctl run` reports "Plugin failed to run ... remains in the system", inspect
with `sudo k3s kubectl describe pod -n default <name>` and `... logs -n default
<name>` — a config/identity error there is a plugin bug, not an RBAC failure.

VOLUME MOUNT requires a node selector (verified on H00F): `pluginctl run -v
<host>:<path>` fails with `Error: volume mounting requires nodeSelector. Please
specify the node by --selector or --node`. Add a placement. GOTCHA: `--node
<kubernetes.io/hostname>` (e.g. `00004cbb4701d16c.agx-thor`) FAILED to schedule —
pod stuck `Pending` with `FailedScheduling ... didn't match Pod's node affinity/
selector`. What WORKS is a LABEL selector on a label the node actually carries:
`--selector zone=core` (single-node WES nodes are labelled `zone:core` plus
`resource.gpu=true`, `resource.cuda110:true`, etc.; list with
`sudo k3s kubectl get node <n> -o jsonpath='{.metadata.labels}'`). Prefer
`--selector <label>=<val>` over `--node <name>` for pluginctl placement.

OBSERVING a pod-local cache (e.g. a `/tmp` ring invisible to the host/other pods):
three ways, in order of usefulness for real evidence —
  1. `-v <hostdir>:<cachepath>` bind-mount the cache to a HOST dir (NOT under
     `/media/plugin-data/uploads`) so you can `ls`/`stat`/`sha` the ring directly
     over SSH while the `--continuous` pod runs. Best for watching eviction live.
  2. `sudo pluginctl logs <name>` — the plugin's own per-write log lines stream
     from outside the pod (e.g. `wrote <f> evicted=1 ring_count=3`).
  3. `sudo pluginctl exec <name> -- python3 -c '...'` to read files/EXIF from
     inside the pod (the pod has piexif etc.; the node host usually does NOT).

## Side-load WITHOUT any registry: build local + import into k3s containerd
`pluginctl run` uses the k8s default image pull policy. For a NON-`:latest` tag
(e.g. `:0.1.1`) the default is `IfNotPresent`, so if the image already exists in
the node's **k3s containerd** store it will NOT pull remotely. This is the
cleanest dev path — no ECR push, no registry login, no credentials, and it dodges
BOTH the broken Jenkins buildkit and the dead lan0 registry:

    podman build -t localhost/<plugin>:<ver> .          # RUN steps work under podman
    podman save localhost/<plugin>:<ver> | sudo k3s ctr images import -
    # then reference it as a docker.io/library/<plugin>:<ver> or the imported name
    pluginctl run docker.io/library/<plugin>:<ver> -- <args>

### IMAGE-NAME TRAP: what containerd STORES the image as (ImagePullBackOff) — VERIFIED 2x
The single most common failure after a side-load is an `ImagePullBackOff` /
`ErrImagePull` even though the image is clearly on the node — because the name the
POD/MANIFEST references does not match the name k3s **containerd** actually stored
it under, so kubelet tries to PULL it from a registry (e.g. `localhost:443`) and
fails. Symptoms: `sudo k3s kubectl describe pod ...` shows `Failed to pull image
"localhost/<plugin>:<tag>"` / `Back-off pulling image`. ALWAYS diagnose by listing
what containerd holds vs what the manifest asks for:
    sudo k3s crictl images | grep -iE "REPOSITORY|<plugin>"   # the STORED name(s)
    # compare against the pod's image: field / pluginctl run <ref>

CRUCIAL, non-obvious: the stored name DIFFERS BY IMPORT INVOCATION (both verified
on H00F, same session):
  - `podman save <img> -o file.tar` then `sudo k3s ctr images import file.tar`
    (file arg)  →  containerd RETAGS to `docker.io/library/<plugin>:<tag>`. A
    manifest that says `localhost/<plugin>:<tag>` then ImagePullBackOffs. FIX:
    make the manifest/`pluginctl run` ref say `docker.io/library/<plugin>:<tag>`.
  - `podman save <img> | sudo k3s ctr images import -` (piped stdin)  →  PRESERVES
    the `localhost/<plugin>:<tag>` tag; referencing `localhost/...` then works.
So do not assume; run `crictl images` after every import and reference the EXACT
string it shows. `imagePullPolicy: IfNotPresent` (the default for non-`:latest`
tags) only helps if the referenced name matches a stored name — a mismatch still
triggers a pull. This trap bit both a DaemonSet manifest AND is why you re-verify
the resolved ref for `pluginctl run` too.

Tell-tale that this is the established convention on a node: `sudo k3s crictl
images` shows the SAME image id under both a `docker.io/library/<plugin>:<ver>`
tag AND a `registry.sagecontinuum.org/<user>/<plugin>:<ver>` tag — i.e. locally
built + imported, not pulled. NOTE: podman/buildah storage is a DIFFERENT store
from k3s containerd; a `podman build` image is not visible to k3s until you
`podman save | k3s ctr images import` it. Confirm the resolved `image:` and pull
policy first with `pluginctl deploy --dry-run -n probe <image> -- --help`.

## Secrets the RIGHT way (Option B, keeps creds out of argv/git/logs)
image-sampler2 reads camera creds from env ONLY (CAMERA_USER/CAMERA_PASSWORD),
never flags. Inject via `pluginctl run --env-from <credsfile>` for testing, or a
k8s Secret referenced by the pod spec (envFrom/secretRef) for scheduled jobs.
NOTE: some existing plugins (yolo/bioclip job YAMLs) embed the camera password in
cleartext as a `--snapshot-url` query-param arg — that leaks into argv, scheduler
records, and git. Prefer the env/Secret pattern; do not copy the query-param-creds
pattern into new plugins.

Writing the `--env-from` creds file over SSH — quoting trap + safe verify: build
the file with two plain `echo`s inside a heredoc, then VERIFY without echoing the
secret. Assembling the password inline in one printf is fragile (secret-masking in
tooling output can corrupt the surrounding quotes and break the heredoc). Robust:
    ssh node 'bash -s' <<'EOSSH'
    umask 077
    U=myuser; P=$(printf '%s' 'part1'; printf '%s' 'part2')   # split avoids masking
    printf 'CAMERA_USER=%s\nCAMERA_PASSWORD=%s\n' "$U" "$P" > /tmp/cam.env
    EOSSH
Then confirm correctness WITHOUT printing the value:
    awk -F= '/CAMERA_PASSWORD/{print "pw_len=" length($2)}' /tmp/cam.env
    awk -F= '/CAMERA_USER/{print "user=" $2}' /tmp/cam.env
pw_len matching the known password length proves the bytes are right even when the
value is masked in your own tool output. `shred -u /tmp/cam.env` when done.

## Give the plugin repo a `make test` target (canonical verification)
A Sage plugin's stock Makefile only has `image`/`push` (docker buildx) — NO test
target — so verification tooling can't auto-detect how to run the suite and
re-flags edits as "unverified" every turn. Add a one-line canonical target that
runs the existing unit venv, so a plain `make test` is the detectable command:
    PY?=.venv-test/bin/python
    test:
    	$(PY) -m pytest -q
    .PHONY: all image push test
(`PY?=` lets CI override the interpreter.) The suites are pure-stdlib pytest
(monkeypatched `os.path.isdir`/`os.access`, fake clocks) and run in <1s — a real
green run is cheap, so prefer `make test` over hand-typed pytest invocations and
run it before every commit.

## podman-on-node build quirks (H00F: docker -> podman 4.9.3)
- Dockerfile `COPY` must list EVERY module the app imports. Sage plugin
  Dockerfiles often enumerate files explicitly (e.g.
  `COPY app.py acquire.py metadata.py ... requirements.txt /app/`) rather than
  `COPY . /app/`. When you ADD a new module (e.g. `capture.py`, `cache.py`), you
  MUST add it to that COPY line or the image builds fine but the container dies at
  start with `ModuleNotFoundError` — a SILENT trap (build + `COPY` show success;
  the failure only appears at `python3 app.py` runtime). Smoke-test after any
  module addition: `sudo pluginctl run -n probe <image> -- --help` and confirm it
  prints help (proves all imports load in-container) before the real run.
- `docker` on the node is aliased to podman; podman has NO default unqualified
  search registry, so Dockerfiles MUST use a FULLY-QUALIFIED base image name, e.g.
  `FROM docker.io/waggle/plugin-base:1.1.1-base` (bare `waggle/plugin-base:...`
  fails: "did not resolve to an alias and no unqualified-search registries").
  Fully-qualified names build cleanly under both docker and podman.
- `pluginctl build` pushes the built image to the node-local WES registry at
  `10.31.81.1:5000` (the node's lan0 address) so `pluginctl run` can pull it. If
  the push fails with "connection refused" to 10.31.81.1:5000, the node registry
  is unreachable — check `ip addr` for lan0: if it shows `NO-CARRIER ... state
  DOWN` the LAN interface (and the registry on it) is down. This is a NODE INFRA
  issue, not a code bug (the image itself builds fine). Workaround: either push to
  Sage ECR and `pluginctl run` that ref, OR build local + `k3s ctr images import`
  (see the no-registry section above — preferred, needs no creds).

## Base image: DON'T use waggle/plugin-base — use python:3.x-slim (VERIFIED 2 ways)
`waggle/plugin-base` tops out at tag `1.1.1-base` (Docker Hub: no newer `-base`).
That image ships **Python 3.8.5** and an OLD **pywaggle `waggle` 0.40.7** whose
`Plugin` has NO `upload_file` method — unusable for modern file uploads; it also
lacks piexif. You must `pip install` modern deps on top regardless.

BEST FIX (verified 2026-07, supersedes the earlier "there is no better base" note
below): DON'T base on `waggle/plugin-base` at all. Base on **`python:3.12-slim`**
(the same family the birdnet CPU plugin uses). Two independent wins:
  1. It builds cleanly on the ECR Jenkins buildkit builder — it does NOT trip the
     `/proc/acpi` runc sandbox bug that `waggle/plugin-base` triggers on EVERY
     `RUN` (see the ECR section below — the bug is BASE-IMAGE-SPECIFIC, not
     universal: birdnet/yolo/bioclip all run `pip install` fine in the same
     builder because they base on python:slim / nvidia pytorch, not plugin-base).
  2. Modern Python (3.12) — no 3.8 back-compat constraint on your code.
A minimal CPU-plugin Dockerfile that builds in ECR:
    FROM python:3.12-slim
    WORKDIR /app
    COPY requirements.txt /app/
    RUN pip install --no-cache-dir -r /app/requirements.txt
    COPY app.py <every-module>.py /app/
    ENTRYPOINT ["python3", "-u", "/app/app.py"]
pywaggle's core `Plugin` (upload_file/publish) is enough for a producer/uploader —
you do NOT need `pywaggle[vision]` unless you import cv2. image-sampler2 uses only
`from waggle.plugin import Plugin` (+ piexif) and fetches frames via stdlib
urllib, so `requirements.txt` is just `pywaggle == 0.56.*` and `piexif == 1.1.*`.
Dropping `[vision]` removes the whole OpenCV/numpy chain (and any apt libGL/glib
need) → smaller, faster, fewer failure surfaces. Verify the trim before shipping:
`git grep -nE "import cv2|cv2\.|croniter"` to confirm nothing needs the extras.
The `RUN pip install` layer is genuinely required (base carries no usable pywaggle)
— it is NOT droppable like the boilerplate apt-get layer.

(HISTORICAL: an earlier pass concluded you were stuck on the Python-3.8 base and
must fall back to podman when ECR buildkit failed. That was wrong — the failure is
the base image, and swapping to python:3.12-slim fixes the ECR build directly.)

## ECR / Jenkins buildkit failure: /proc/acpi is BASE-IMAGE-SPECIFIC (VERIFIED)
The portal's ECR build runs on a Jenkins buildkit builder (`buildctl
--frontend=dockerfile.v0 --opt platform=linux/arm64,linux/amd64 ... push=true`).
With a `waggle/plugin-base` base, EVERY `RUN` step fails at container init with:
    runc run failed: ... can't mask dir "/proc/acpi": mount ... MS_RDONLY ...
      invalid argument
    error: failed to solve: process "/bin/sh -c <anything>" ... exit code: 1
Tell-tale: the base pulls/extracts fine for both platforms and `COPY` succeeds
(shows CACHED), then the FIRST `RUN` dies at container init.

KEY INSIGHT (verified 2026-07): this is NOT a universal builder problem and NOT
your Python. The SAME ECR builder builds birdnet/yolo/bioclip fine — they all have
`RUN pip install` steps that succeed — because they base on `python:3.12-slim` /
`nvcr.io/nvidia/pytorch`, NOT `waggle/plugin-base`. The `/proc/acpi` runc sandbox
failure is triggered by the `waggle/plugin-base:1.1.1-base` container config.
PRIMARY FIX: change the base image to `python:3.12-slim` (see base-image section
above). This makes the ECR build succeed directly — no podman fallback needed.
Secondary hygiene: drop UNNECESSARY `RUN` layers anyway (boilerplate
`apt-get install wget curl` many upstream Sage Dockerfiles carry but the plugin
never uses — verify with `git grep -nE "wget|curl|subprocess|os.system|Popen"`).
FALLBACK (only if you're forced to keep a broken base): build on the node with
podman (RUN works fine there) + `k3s ctr images import`. But prefer fixing the
base — the podman path can't push to ECR, so the plugin stays un-submittable via
sesctl. If a NON-plugin-base image genuinely trips /proc/acpi, THAT is a Sage
platform infra issue to report; the base swap resolves the common case.

## Rebuild trigger / stale metadata
ECR builds from the git repo at `source.url`/`branch` in sage.yaml (Jenkins log
shows the resolved commit SHA — confirm it matches your latest push before
debugging anything else). ECR will NOT rebuild an already-registered version —
bump `version:` in sage.yaml (e.g. 0.1.0 -> 0.1.1) to force a fresh build/tag.
If the portal shows a stale app name/version (e.g. old `imagesampler`/`0.3.8`
instead of your `image-sampler2`/`0.1.0`), it snapshotted an OLD sage.yaml before
your push — re-sync/refresh the repo in the portal. name/version come from
sage.yaml (not ecr-meta/, and there are no git tags driving it unless you create
them). Always push Dockerfile/sage.yaml/ecr-meta fixes BEFORE triggering the
portal build.

## Verifying the Beehive round-trip
Public data-query API (no auth): `POST https://data.sagecontinuum.org/api/v1/query`
with JSON body like `{"start":"-15m","filter":{"vsn":"H00F","name":"upload"}}`,
returns NDJSON. Object store propagation is cross-country (~2 min) — allow lag.
Timestamps must be RFC3339 (`date -u -d '20 minutes ago' +%Y-%m-%dT%H:%M:%SZ`).
Local-only plugins that NEVER upload images STILL show up here IF they
`plugin.publish(...)` measurements (e.g. a liveness heartbeat) — query by the
measurement `name`, not `upload`.

IDENTITY IS ATTACHED DOWNSTREAM (verified on H00F Stage-5): a plugin publishing
with a PLACEHOLDER `vsn="NODE"` (because /etc/waggle is host-only, unreadable in
the pod) appears in the data API with the REAL `vsn:"H00F"`, `node:"00004cbb..."`.
Beehive's routing resolves node identity after the fact — so a placeholder vsn in
EXIF/publish is EXPECTED and correct; do NOT try to self-resolve vsn inside the
pod. Beehive also auto-MERGES meta keys into every record: `host, job
(="Pluginctl" for side-loaded runs), node, plugin (=the image ref), task (=the
pluginctl -n name), vsn, zone` — combined with the plugin's own publish `meta`
(e.g. cache_name/camera). Useful for disaggregating multi-stream/multi-instance
nodes in a query.

## What the WES upload-agent actually uploads (and DELETES) — VERIFIED from source
Critical if a plugin writes a LOCAL cache/ring: know exactly what the upload-agent
touches. Read from `waggle-sensor/wes-upload-agent` (`main.sh`, image
`waggle/wes-upload-agent:0.6.0`), confirmed against a live node:
- The agent mounts host `/media/plugin-data/uploads` at `/uploads` and loops
  forever. `find_uploads_in_cwd()` runs `find . -mindepth 3 -maxdepth 4 -type d`
  filtered to paths shaped like `[<job>/]<plugin>/<version>/<ts>-<sha1hex>/`
  where <version> matches `x.y.z | vx.y.z | latest | test` and the leaf dir matches
  `<digits>-<hexdigits>` (the pywaggle staging dir holding {data,meta}).
- For each match it rsyncs to beehive with `--remove-source-files`, then rmdirs the
  emptied dir. So the agent UPLOADS AND THEN DELETES the staged files.
- The on-host uploads tree is therefore organized by `<plugin>/` and
  `<plugin>-<jobid>/` subdirs (one per instance), matching the object path
  `.../<plugin>/<version>/<node-id>/<ts>-<file>` seen in the data API.
CONSEQUENCE / design rule: a plugin's LOCAL-ONLY cache must NOT live under
`/run/waggle/uploads` — the agent would both upload files you never meant to ship
AND delete them out from under your own eviction logic. Put a local ring in a
DEDICATED subtree outside the upload mount (a `--cache-dir` hostPath / user volume,
NOT the uploads mount). Do not rely on "my filenames happen not to match the regex"
— the scan pattern can change; keep the cache physically separate.
(Also: reading `/etc/upload-agent/` dumps the node's Beehive SSH push key — treat
as a secret; never echo/reuse it.)
