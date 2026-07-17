# SES scheduling gotchas + network-camera audio/video sourcing

Hard-won detail from running BirdNET / YOLO / BioCLIP plugins on Thor node H00F
against a Reolink hummingcam. Keep SKILL.md lean; this file carries the specifics.

## 1. SES scheduling requires the app in the ECR CATALOG — not just the Docker registry

Symptom: `sesctl submit -j <id>` returns
`400 Bad Request: {"error": "[registry.sagecontinuum.org/<ns>/<app>:<ver> does not exist in ECR]"}`
even though `docker pull` / `pluginctl` work fine for that exact image.

Why: two different stores.
- **Docker registry** (`registry.sagecontinuum.org/<ns>/<app>:<ver>`): raw image blobs.
  `pluginctl` pulls from here directly and runs node-locally. Pushing an image here does
  NOT register an app.
- **ECR app catalog** (`ecr.sagecontinuum.org`): the registered-app database the cloud
  scheduler (SES) validates against. Populated ONLY by registering + building the app
  through the ECR portal (portal.sagecontinuum.org/apps), which reads the GitHub repo's
  `sage.yaml` + `Dockerfile` from the repo root.

Consequence: a plugin can pass all `pluginctl` testing yet fail `sesctl submit`. The job is
still created (keeps its numeric ID); it submits cleanly the moment the app appears in the
catalog. Verify catalog presence first via Sage MCP `find_plugins_for_task` or the ECR app
list — if your app name isn't in that list, scheduling will 400.

Fix: portal.sagecontinuum.org/apps → Create app → point at repo + branch → build (at least
the arch your node needs; H00F = linux/arm64). Then `git pull` on the node, `sesctl submit -j <id>`.

Known multi-arch pitfall: arm64 QEMU emulation can crash on NVIDIA base images during the
portal build; if arm64 fails there, a native arm64 builder from the ECR manager is needed.

## 2. sage.yaml inputs: ONLY `string` and `int`

ECR app validation rejects `type: "float"` and `type: "bool"`. A sage.yaml with float types
passes local YAML lint but fails the portal build. Declare float-valued args
(`min-confidence`, `duration`, `lat`, `lon`, `overlap`, `sensitivity`, `sf-thresh`,
`interval`, …) as `type: "string"`; parse numerically in argparse at runtime. For argparse
`store_true` flags, use `type: "string"` and note in the description it's presence-only.

## 3. sesctl CLI flag/identifier reality (verified on H00F)

The Sage website docs (https://sagecontinuum.org/docs/reference-guides/sesctl) and the linked
edge-scheduler README are STALE. Actual installed binary:
- Create: `sesctl create -f <file>` / `--file-path` — the docs' `--from-file` errors with
  `unknown flag: --from-file`.
- Submit/stat/rm: operate on a **numeric job ID** via `-j`/`--job-id`, NOT a job name.
  - `sesctl create -f job.yaml` → prints a numeric job ID
  - `sesctl stat` → list jobs and IDs; `sesctl stat -j <id>` → one job
  - `sesctl submit -j <id>` (add `--dry-run` to validate); `sesctl rm -j <id>`
- `--server` defaults to `https://es.sagecontinuum.org`; pass `--server` / `--token`
  explicitly if env vars aren't picked up.

## 4. Network-camera audio/video: auth method is camera-vendor-specific

ffmpeg input URL auth differs by camera and is a frequent silent failure:

- **Reolink (RLC-811A) BCS/FLV**: credentials MUST be **query parameters**, NOT HTTP basic
  auth. Basic auth (`http://user:pass@ip/...`) returns ffmpeg `Error opening input: End of
  file` / **exit 187**. Working form (single-quote it in shells — `!` triggers history
  expansion, and `&`/`?` need quoting):
  `'http://IP:PORT/flv?port=1935&app=bcs&stream=channel0_sub.bcs&user=USER&password=CAMERA_PASSWORD'`
  The sub-stream carries ~16 kHz audio → use `--bandpass-fmax 8000`.
- **Mobotix (M16) MxPEG**: uses HTTP **basic auth** (`http://user:pass@ip/control/faststream.jpg?stream=MxPEG&needlength`).
  Native audio is pcm_alaw 8 kHz (4 kHz Nyquist) → `--bandpass-fmax 4000`, marginal for birdsong.

Consumer Reolink cams expose NO mic input-gain/sensitivity control (the web-UI "Volume" is
SPEAKER output for two-way talk, not mic gain). The only "Record Audio" toggle just enables
the mic. So for faint audio the only lever is downstream gain in the ffmpeg capture. Note:
BirdNET does NOT normalize/AGC input amplitude (librosa loads samples as-is; `sensitivity`
shapes output logits, not input gain) — so a measured fixed `volume=NdB` boost is the right
remedy, and you don't risk double-leveling. Prefer fixed gain over dynaudnorm/loudnorm
(those compress dynamics and lift the noise floor, hurting SNR).

## 5. pluginctl "pod updates may not change fields" on redeploy

`pluginctl deploy -n <name> ...` against an existing pod fails with
`Forbidden: pod updates may not change fields other than spec.containers[*].image ...`
because k8s only allows the image field to change on a running pod. Fix: `pluginctl rm
<name>` first, wait a few seconds, then deploy. If stuck Terminating:
`kubectl delete pod <name> --grace-period=0 --force`.

## 5b. Cron one-shot is the DEFAULT model — long-running pods are the exception

The Sage-native execution model is **one-shot cron**: the scheduler fires a container, it
captures → infers → publishes → exits (typically 30–40s), then k8s removes the pod; repeat
every N minutes. SKILL.md's scheduling table lists Cronjob as "Most common". So:

- SES-scheduled cron pods run in the **`ses` namespace** (not the default pluginctl namespace).
  Catch one mid-tick with `kubectl get pods -n ses | grep <plugin>`; between ticks there is NO
  pod. Seeing it Running for ~45s then gone on the next check is correct behavior, not a crash.
- **Portal node page only surfaces persistent/long-running plugins.** A 40-s-every-10-min cron
  job is invisible there between ticks — a frequent "is my job even running?" confusion. Verify
  via `kubectl get pods -n ses`, `sesctl stat -j <id>`, and the data API (query the always-published
  summary measurement, e.g. `env.detection.audio.summary`), NOT the node page.
- Continuously-running pods (e.g. a YOLO/BioCLIP `app.py` launched with `--continuous Y` or
  `--num-recordings 0 --interval ...`) are the LESS common pattern. They keep the model warm
  (low per-inference latency, high cadence, visible on the node page) but hold GPU/RAM the whole
  time. Cron trades a per-cycle cold-start (model reload each run — fine for CPU/TFLite like
  BirdNET) for auto-restart resilience and freed resources between runs. Pick continuous only
  when you need always-on / high-frequency watching; otherwise cron is the default.

## 6. pluginctl vs the watcher: detection plumbing is not auto-wired

When two model plugins run on the same camera (e.g. YOLO object-counter + a BioCLIP species
classifier), a downstream consumer (Slack watcher etc.) only sees what it explicitly polls.
Example failure: YOLO publishes `env.count.fire_hydrant` (a COCO false-positive on a fixed
object in frame) while BioCLIP confidently IDs hummingbirds — but a watcher that triggers on
`env.count.bird` stays silent for hours because the two plugins aren't connected. COCO/YOLO
gives only a coarse `bird` class and is prone to phantom classes; species ID comes from
BioCLIP/BirdNET. If you want to alert on species, poll `env.species.*` with a confidence
threshold as an independent trigger path — don't assume YOLO firing is a prerequisite.

## MCP quirk

`get_cloud_images` / `get_image_data` auto-prepend "W" to the node id (queries "WH00F" for
H00F), so they miss Thor/non-W nodes. Use the data API directly or `pluginctl logs` on the
node as ground truth for those.
