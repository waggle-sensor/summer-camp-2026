# SES vs pluginctl: Deployment Model & Diagnostics

Operational truths learned deploying audio/vision plugins on Thor node H00F.

## The two deployment paths produce DIFFERENT namespaces

This is the single most useful diagnostic on a node. `kubectl get pods -A`:

| Namespace | Means | Lifecycle |
|-----------|-------|-----------|
| `ses` | Launched by the SES **cloud scheduler** (official, from a submitted job) | Short-lived cron pod: spawns, runs, publishes, exits, gets cleaned up |
| `default` | Hand-deployed directly with `pluginctl deploy` on the node | Whatever the args say — often a long-running `--continuous Y` pod |

So to answer "is this an official scheduled job or a hand-launched test pod?" just check the namespace. A pod in `default` with multi-day uptime is a hand-deployed continuous pod, NOT a scheduled job — even if you intended it to be scheduled.

## "Most Sage jobs are one-shot, not long-running"

The canonical Sage pattern is the **cron one-shot**: scheduler fires a container every N min, it captures → infers → publishes → exits (~30–60s). Long-running `--continuous Y` pods (model stays warm, loops internally every `--interval` s) are the EXCEPTION, usually an artifact of test-deployment style that became the de-facto deployment.

Tradeoff when deciding between them:
- **One-shot cron**: frees GPU/RAM between runs; scheduler auto-restarts; survives reboots; the "Sage-native" managed style. COST: cold model reload every cycle. Cheap for small TFLite/CPU models (BirdNET ~seconds); expensive for big GPU models (BioCLIP 2.5 ViT-H/14 cold start can be 30–90s+, and churns 16–32Gi allocations each tick).
- **Continuous pod**: model loads once, warm, low per-inference latency, high cadence. COST: pins GPU/RAM 24/7; dies silently if it crashes (no scheduler restart); invisible to SES; not on the portal node page as a job.
- **Hybrid**: keep the heavy model warm/continuous, convert the light one to cron.

Rule of thumb: if the target cadence is sparse (e.g. every 10 min) and the GPU is otherwise idle, prefer one-shot cron UNLESS cold-start is a large fraction of the run — measure cold-start first for big models before committing.

## Why a scheduled job is "invisible" on the portal node page

The portal node page (`portal.sagecontinuum.org/nodes/<VSN>`) surfaces persistent/long-running plugins. A cron job that lives ~40s every 10 min has no pod between ticks, so it won't show there. That's expected, not a failure. Confirm it differently (below).

## How to check a scheduled job is really running

1. **Is it scheduled in SES?** (by numeric job ID — this sesctl build is ID-based, not name-based):
   ```bash
   sesctl --server https://es.sagecontinuum.org --token "$SES_USER_TOKEN" stat -j <JOB_ID>
   ```
2. **Did it actually fire on the node?** Catch the ephemeral pod between ticks:
   ```bash
   sudo kubectl get pods -n ses | grep <plugin>
   ```
   You may only catch it for a few seconds (`Running 45s`) before it exits and is cleaned up. To capture its logs, watch in a loop for the next cron tick, then `kubectl logs -n ses <pod>` immediately.
3. **Is it publishing?** Query Beehive for the per-cycle measurement the plugin always emits (e.g. a `...summary` topic), not just detection topics that only appear on a positive hit. Empty summary over several cycles = job failing before publish, or first cycle hasn't propagated yet.

## ECR registration is a hard gate for SES (but NOT for pluginctl)

`sesctl submit` returns `400 ... <image> does not exist in ECR` even when `docker pull`/`k3s ctr pull` of that exact image works. Reason:
- **pluginctl** pulls from the raw Docker registry (`registry.sagecontinuum.org/...`) → node-local, no catalog check. This is why hand-deployed test pods work.
- **SES scheduler** validates the image against the **ECR app catalog** (`ecr.sagecontinuum.org`). An app only lands in the catalog when built/registered through the ECR **portal pipeline** (from the GitHub repo + `sage.yaml` + `Dockerfile`). Pushing/pulling a Docker image alone does NOT register it.

So: image pullable ≠ app registered. The job can be `create`d (gets an ID) and will only `submit` cleanly once the ECR portal build is green. Verify catalog presence via the Sage MCP `find_plugins_for_task` (lists registered apps) — if your plugin name isn't there, it's not registered.

## Reading other jobs' schedules from the SES jobs API (authoritative)

To find the exact cron period a deployed plugin uses (instead of inferring from data timestamps), read the job spec directly — the `scienceRules` field holds the cron rule:
```python
import json, urllib.request
data = urllib.request.urlopen("https://es.sagecontinuum.org/api/v1/jobs/list", timeout=30).read().decode()
jobs = json.loads(data)
jobs = jobs.values() if isinstance(jobs, dict) else jobs
for job in jobs:
    if "avian" in json.dumps(job).lower():
        print(job.get("job_id"), job.get("name"),
              list((job.get("nodes") or {}).keys()),
              job.get("science_rules") or job.get("scienceRules"))
```
The rule looks like `schedule("avian-diversity-monitoring"): cronjob("avian-diversity-monitoring", "*/5 * * * *")`.
Empirical note: the same plugin runs at different periods per project — avian-diversity-monitoring observed at `* * * * *` (1 min, dedicated monitoring), `*/5` (common default), and `*/20`. Don't assume one fixed period.

## Inferring period from data timestamps is unreliable

Computing inter-cycle gaps from `env.detection.*` records UNDER-samples: cycles where your queried species weren't detected are missing, inflating gaps. Within a single capture cycle, many species share ~the same timestamp (gaps of a few seconds). Use the job spec (above) for the real period; only fall back to timestamps if the job isn't in the list.
