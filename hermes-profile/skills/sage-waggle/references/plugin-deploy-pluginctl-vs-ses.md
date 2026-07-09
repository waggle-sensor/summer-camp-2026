# Plugin deploy: pluginctl side-load vs SES, podman gotchas, creds via Secret

Learned building/deploying image-sampler2 on node H00F (Thor, aarch64), 2026-07.

## Two deploy paths

| Path | ECR registration needed? | Gives real Beehive round-trip? | Tool |
|------|--------------------------|-------------------------------|------|
| **Side-load** | NO | YES — runs the image in a real WES pod with full upload plumbing (RabbitMQ, `/run/waggle/uploads` -> upload agent -> Beehive) | `pluginctl run` |
| **Scheduler** | YES (ECR app metadata AND image both must exist — two distinct failure modes) | YES | `sesctl` (create/submit) |

For quick verification of the upload path, **use `pluginctl`** — it bypasses the ECR
registration gate entirely. Register in the portal only when moving to scheduled SES jobs.

`pluginctl run` key flags:
- `PLUGIN_IMAGE [-- ARGS...]` — image ref then plugin args after `--`
- `-e/--env KEY=VAL` and `--env-from FILE` — inject env (use for secrets; keeps them out of argv/process listing)
- `--selector resource.gpu=true`, `--resource`, `--node`, `-v/--volume`
`pluginctl build PLUGIN_DIR` returns an image ref for `pluginctl run -n name $(pluginctl build dir)`.

## Node uses PODMAN (not Docker)
`docker` on the node is aliased to **podman** (4.9.3 on H00F). Consequences:
- Dockerfiles MUST use a **fully-qualified base image name**: `FROM docker.io/waggle/plugin-base:1.1.1-base` (podman has no default unqualified-search registry; a bare `waggle/plugin-base:...` fails with "did not resolve to an alias").

## H00F node-local registry often DOWN
`pluginctl build` pushes the built image to the node-local WES registry at
`10.31.81.1:5000` (on the `lan0` interface). On H00F `lan0` is frequently
`NO-CARRIER / state DOWN`, so that push fails (`connection refused`). Workaround:
push the image to **Sage ECR** (`registry.sagecontinuum.org/<namespace>/<name>:<ver>`)
and `pluginctl run` that fully-qualified ref — pulls over WAN, sidestepping lan0.

## Camera credentials: env-only via Secret (do NOT copy yolo/bioclip)
The existing yolo/bioclip plugins embed the camera password in the job-YAML args as a
cleartext query-param URL (`...&user=...&password=CAMERA_PASSWORD...`) — it lands in argv,
`kubectl describe pod`, scheduler records, AND is committed to git. This is a leak.

image-sampler2 is deliberately **env-only**: reads `CAMERA_USER`/`CAMERA_PASSWORD`
from the environment, never as flags/argv. Inject via a k8s Secret (`envFrom`/`secretRef`
in the SES pod spec) or `pluginctl run --env-from <file>`. NEVER put the password in
args or commit it. (Test camera user for the H00F hummingcam exploration: username
`test`; ask Pete for the current password — do not store it.)

## Dockerfile must COPY all modules
image-sampler2 split into acquire.py / metadata.py / nodemeta.py / upload.py / app.py.
The Dockerfile COPY line must include ALL of them, or the built image crashes on import.

## sage.yaml drives ECR name/version
The portal reads app **name** and **version** from `sage.yaml` (`name:`, `version:`),
NOT from ecr-meta/. If the portal shows a stale name/version, it snapshotted an old
commit before the push — re-sync the repo/branch in the portal so it reads current HEAD.
No git tag is required (the version field, not a tag, is authoritative here).
