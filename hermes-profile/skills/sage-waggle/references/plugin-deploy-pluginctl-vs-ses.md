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
`NODE_CONTROL_PLANE_IP:5000` (on the `lan0` interface). On H00F `lan0` is frequently
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

## STOPPING a scheduled job: must be done at the CLOUD (SES), not locally
To free GPU/space on a node you often need to stop running science jobs (e.g. yolo/
bioclip). The node scheduler (`nodescheduler` pod `wes-plugin-scheduler` in `default`)
runs with `-goalstream-url https://es.sagecontinuum.org/api/v1/goals/<VSN>/stream` —
**goals are STREAMED FROM THE CLOUD**. Consequences (learned freeing H00F, 2026-07):
- Deleting the pod (`kubectl delete pod`) does NOT stick — jobs are short-lived pods
  the scheduler re-spawns each cron tick; the pod you see may already be gone.
- Editing/removing the local `waggle-plugin-scheduler-goals` configmap does NOT stick
  (it's empty anyway) — the node re-syncs goals from the cloud stream within seconds.
- There is **no goals CRD** on the node (`kubectl get wagglejobs/goals/...` → "server
  doesn't have a resource type") and the scheduler API is NOT on node `localhost:9770`.
- The ONLY durable stop is via **SES with the user's token**:
  ```sh
  sesctl --server https://es.sagecontinuum.org --token "$SES_USER_TOKEN" stat -A   # find job IDs
  sesctl --server https://es.sagecontinuum.org --token "$SES_USER_TOKEN" rm --suspend -j <id>
  ```
  `sesctl` exists on the node (`/usr/bin/sesctl`) AND bundled in the scheduler pod
  (`/app/sesctl-linux-arm64`), but BOTH need a valid token — there is none on the node
  and none in env by default. **If you don't have `$SES_USER_TOKEN`, STOP and ask the
  user for it** — do not fake a local stop that won't hold for the test's duration.

## Finding the real job names to stop
Job/goal names are NOT always what the user calls them ("Yolo"/"BioClip" ≠ pod names).
Discover the actual scheduler goals from the scheduler log:
```sh
sudo kubectl logs -n default deploy/wes-plugin-scheduler --tail=200 \
  | grep -oE "The goal [a-z0-9-]+ exists" | sort -u
```
On H00F this revealed: `yolo-hummingcam`, `bioclip-hummingcam`, `insect-bioclip`,
`sage-vision-detect-bioclip-h00f`, `birdnet-reolink`, `edgerunner-demo`. Map the
user's shorthand to these exact names and CONFIRM scope before suspending (one label
like "bioclip" often maps to several goals). Thor's `nvidia-smi` returns `[N/A]` for
memory — use tegrastats for GPU headroom, not the standard nvidia-smi query.

## Dockerfile must COPY all modules
image-sampler2 split into acquire.py / metadata.py / nodemeta.py / upload.py / app.py.
The Dockerfile COPY line must include ALL of them, or the built image crashes on import.

## sage.yaml drives ECR name/version
The portal reads app **name** and **version** from `sage.yaml` (`name:`, `version:`),
NOT from ecr-meta/. If the portal shows a stale name/version, it snapshotted an old
commit before the push — re-sync the repo/branch in the portal so it reads current HEAD.
No git tag is required (the version field, not a tag, is authoritative here).
