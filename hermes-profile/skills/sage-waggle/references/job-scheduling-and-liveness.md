# SES Job Scheduling, Deployment Style & Liveness Checks

Hard-won operational knowledge for running ECR plugins as scheduled jobs and
verifying they're alive. Companion to the "Container Runtime & Scheduling Model"
section in SKILL.md.

## sesctl CLI — flags differ from the published docs

The Sage website docs (https://sagecontinuum.org/docs/reference-guides/sesctl)
and the linked edge-scheduler README are WRONG/outdated for the installed
binary. Verified on H00F:

| Action            | Docs say (WRONG)        | Actual binary                          |
|-------------------|-------------------------|----------------------------------------|
| Create job        | `create --from-file f`  | `create -f f` / `--file-path f`        |
| Submit/activate   | `sub <job-name>`        | `submit -j <numeric-job-id>`           |
| Status            | `stat <job-name>`       | `stat` (list) / `stat -j <job-id>`     |
| Remove            | `rm <job-name>`         | `rm -j <job-id>`                        |

- `--from-file` → `unknown flag: --from-file`. Use `-f`/`--file-path`.
- submit/stat/rm operate on a **numeric job ID** (`-j`), not a name.
- `create` returns the job ID; capture it. `--server` default is now
  `https://es.sagecontinuum.org` on recent builds; `--token` from the portal.
- sesctl is usually already installed on nodes (e.g. `/usr/bin/sesctl` on Thor).
  If installing fresh, grab `sesctl-linux-arm64` from
  github.com/waggle-sensor/edge-scheduler/releases (nodes are aarch64).

## Removing/suspending a job: suspend-first, and `rm -s` IS suspend

`sesctl rm` is "remove OR suspend" in one subcommand. Flags:
- `rm <job-id>` — remove. REJECTED on a Running job:
  `Failed to remove job "<id>" as it is in running state. Suspend it first or
  specify force=true`.
- `rm -s <job-id>` / `--suspend` — suspend (pause; keeps the job record).
- `rm -f <job-id>` / `--force` — remove/suspend forcefully (skips the
  suspend-first requirement).
- JOB_ID is POSITIONAL: `rm [FLAGS] JOB_ID` (e.g. `rm -s 5645`), not `-j`.
  (Confusingly, `submit`/`stat` use `-j <id>`, but `rm` takes the id
  positionally. Run `sesctl rm --help` to confirm.)

Clean stop sequence for a running job: `rm -s <id>` (suspend) → `rm <id>`
(remove) → `stat -j <id>` shows `Removed`. Or one-shot with `rm -f <id>`.
A removed job's pods disappear from the `ses` namespace immediately.

## Token scope: read ops can pass while write ops 401 with the SAME token

A Sage user token can be scoped read-only: it succeeds on `stat` (read) but
returns `401 Unauthorized / "Invalid token."` on `rm`, `rm -s`, `submit`
(write/scheduling ops) — same token, same syntax, same server. So a 401 on a
write op does NOT necessarily mean a transmission or quoting bug; verify scope
by re-running a READ op (`stat -j <id>`) with the identical inline token. If
read passes and write 401s, the token lacks scheduling permission — get a
write-scoped token from portal.sagecontinuum.org/account/access (or use the
shell/session whose token originally created+submitted the job; that one has
write scope by definition).

## Converting hand-deployed continuous pods to cron — check the image source first

Before writing cron YAMLs to "promote" a hand-deployed plugin, inspect what
image the running pod actually uses:
`sudo kubectl get pod <name> -n default -o jsonpath="{.spec.containers[0].image}"`.
A `docker.io/library/<img>:<ver>` prefix means it's a LOCAL containerd build
(built on the node + `k3s ctr images import`), never pushed/registered to ECR.
SES will reject it with the "does not exist in ECR" 400 (see below). So the
real first step of any continuous→cron conversion is ECR registration of that
plugin's repo — not the YAML. Don't draft+submit cron jobs until the image is
an ECR app.

## Two ECR failure modes (both produce non-working jobs)

### Mode 0: ARM64 build QEMU crash (pipeline can't build at all)

The ECR Jenkins pipeline runs on x86 and uses QEMU to emulate arm64. NVIDIA
base images (nvcr.io/nvidia/pytorch:25.08-py3) crash under QEMU emulation with
SIGABRT (exit 134) during `pip install`:

    qemu: uncaught target signal 6 (Aborted) - core dumped

Removing `linux/amd64` from sage.yaml does NOT help — the arm64 build itself
runs via QEMU-on-x86. **Workaround: build natively on Thor (arm64) and push
manually:**

```bash
# 1. Login (use Sage portal access token as password)
sudo docker login registry.sagecontinuum.org -u beckman

# 2. Build with full registry tag
sudo docker build -t registry.sagecontinuum.org/beckman/<app>:<ver> .

# 3. Push
sudo docker push registry.sagecontinuum.org/beckman/<app>:<ver>
```

MUST use `sudo` for login, build, AND push (credentials stored per-user under
root). SES cron jobs auto-succeed on the next tick once the image is pullable.

### Mode 1: "does not exist in ECR" (400 at submit time)

`sesctl submit` validates the image against the **ECR app catalog**
(ecr.sagecontinuum.org), NOT the raw Docker registry. An image that
`pluginctl`/`docker pull` can fetch from `registry.sagecontinuum.org/...` will
still fail SES submit with:

    400 Bad Request: [registry.sagecontinuum.org/<ns>/<img>:<tag> does not exist in ECR]

if the app was never registered/built through the ECR portal (build pipeline
reads sage.yaml + Dockerfile from the GitHub repo root). Fix: register + build
the app in the portal first.

### Mode 2: App registered but image never built (ErrImagePull at runtime)

The ECR portal has TWO layers: app metadata (name, inputs, science description)
AND the actual Docker image artifact. You can create/register an app page AND
have `sesctl submit` succeed (SES validates app metadata) but the Docker image
was never built/pushed. Result: SES shows "Running" but every cron tick produces:

    kubectl get events -n ses:
    Failed to pull image "registry.sagecontinuum.org/<ns>/<img>:<tag>":
    not found
    Error: ErrImagePull

Fix: trigger a build on the ECR portal for the specific version/tag. The cron
jobs auto-succeed once the image is pullable — no need to recreate/resubmit.

Diagnosis: `sesctl stat` says Running but `kubectl get events -n ses` shows
ErrImagePull. The portal app page may show "Tagged Versions (1)" but no actual
built image behind it.

## sage.yaml input types: string/int safest, but float may work

ECR docs say only `string` and `int` are supported, and the birdnet build
needed `float→string` conversion. However, yolo-object-counter 0.2.0 built
successfully WITH `type: "float"` inputs (conf-thres, iou-thres). So ECR may
now accept floats. **Safest practice:** use `string` for float-valued args
(argparse parses them at runtime). But don't panic-fix an already-working build
that has floats. Boolean store_true flags → `string`, presence-only.

## Deployment style: one-shot cron is the default, not continuous pods

- **Cron one-shot** (the Sage-native default): scheduler fires a pod every N
  min; it captures → infers → publishes → exits in ~30–60s. Frees GPU/RAM
  between runs, auto-restarts, survives reboots. Right choice when cadence is
  minutes apart.
- **Continuous pod** (`--continuous Y --interval 60`, hand-deployed via
  pluginctl): model loads once, loops forever, pins GPU/RAM 24/7, dies silently
  on crash (no scheduler restart), invisible to SES. This is a TEST/iteration
  convenience that often gets left in place as a de-facto deployment — usually
  wrong if the real cadence is ~10 min. Only justified when cold-start model
  load is a large fraction of each cycle.
- **Cold-start consideration:** BioCLIP 2.5 ViT-H/14 (large model, 16-32Gi)
  may take 30-90s+ to reload each cron tick. Measure with a test one-shot run
  before committing to cron. If cold start > ~2 min, keep it continuous or use
  the hybrid approach (bioclip continuous, lighter models as cron).

### Avian-diversity-monitoring baseline schedules (June 2026)

Queried from live SES job specs (es.sagecontinuum.org/api/v1/jobs/list):
- sage-utah-job (W029): `*/5 * * * *` (5 min)
- sage_badriver (W083): `*/5`
- sage_paintbrush (W06D): `*/5`
- sage_w028 (W028): `*/20`
- AvianPopUp (W097): `* * * * *` (every 1 min)
- Avian (W01B/W020/W023/W028): `* * * * *` (every 1 min)

Data publishes as `env.detection.avian.<species>` (contrast with birdnet V2.4's
`env.detection.audio.<species>` + `env.detection.audio.summary`).

## Namespace tells you who launched a pod

- `ses` namespace = SES cloud scheduler (a real scheduled job).
- `default` namespace = hand-deployed `pluginctl deploy` (test pod).
- `sudo kubectl get pods -A | grep -iE "<name>"` shows pod + namespace.

When converting from pluginctl to SES: don't `pluginctl rm` the old pod until
the new SES cron job is verified publishing data — otherwise you get a coverage
gap. But do remove it once verified, or you get double inference + double data.

## Checking a cron job is alive (3 checks, most-reliable last)

1. SES state: `sesctl stat -j <job-id>` → Submitted/Running.
2. Pod firing: `sudo kubectl get pods -n ses | grep <name>` (catch mid-tick;
   GC'd within ~40s so `kubectl logs` usually races and loses).
3. **Data-API heartbeat** (definitive): query the plugin's per-cycle summary
   measurement over the last few intervals. Only works if the plugin ALWAYS
   publishes (see next section).

The portal node page only surfaces persistent pods — a healthy cron job is
INVISIBLE there between ticks. That's expected, not a fault.

## ALWAYS publish a heartbeat/summary, even on empty cycles

Common plugin bug: guarding the summary publish with `if detections:` so quiet
cycles publish nothing. Then the data API can't distinguish "running fine, no
detections" from "job is dead" — there's no liveness signal. Fix: always publish
the summary topic (e.g. `env.detection.audio.summary`) with `total_detections:
0` on empty cycles. The per-detection publish loop naturally no-ops on an empty
list, so only the summary needs un-guarding. This matches the convention of
mature Sage plugins and is what enables data-API liveness checks above.

## Data API query gotchas

- No wildcard suffix: `"name": "env.detection.audio.~"` (or `.*`) →
  `invalid filter field pattern`. Use exact measurement names, or filter by
  `task`/`plugin`. (`task` filtering worked for aggregating all of a node's
  avian records; `plugin: "<image>.*"` regex also works.)
- The Sage MCP image tools auto-prepend "W" to node IDs, breaking Thor-style
  VSNs like H00F (queries become "WH00F" → no results). Hit the data API
  directly with curl for those nodes.
- Read the full job list (incl. scienceRules) from
  `https://es.sagecontinuum.org/api/v1/jobs/list` (large NDJSON/JSON; grep for
  the plugin name to find cron rules across all projects).
