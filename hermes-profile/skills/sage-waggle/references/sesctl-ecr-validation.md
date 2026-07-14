# sesctl job scheduling: CLI reality + ECR-catalog validation

Official docs:
- [Sage sesctl reference](https://sagecontinuum.org/docs/reference-guides/sesctl)
- [edge-scheduler sesctl tutorials](https://github.com/waggle-sensor/edge-scheduler/tree/main/docs/sesctl)
- Related: [pluginctl reference](https://sagecontinuum.org/docs/reference-guides/pluginctl) · [pluginctl tutorials](https://github.com/waggle-sensor/edge-scheduler/tree/main/docs/pluginctl) · [Edge apps](https://sagecontinuum.org/docs/category/edge-apps)

Session-verified notes (H00F, June 2026). The published web docs and this
skill's older `sesctl` snippet drifted from the actual shipped binary. Always
run `sesctl <subcmd> --help` to confirm flags.

## CLI flag reality (this build)

- `sesctl create -f job.yaml` — the flag is `-f` / `--file-path`, NOT
  `--from-file`. Using `--from-file` errors: `unknown flag: --from-file`.
- `create` returns a **numeric job ID**. Capture it.
- `sesctl submit -j <job-id>` — submit/activate by **job ID**, not job name.
  Same for `stat -j <id>` and `rm -j <id>`. There is no `sesctl sub <name>`.
- `sesctl submit -j <id> --dry-run` — validate without committing.
- `--server` / `--token` flags override `SES_HOST` / `SES_USER_TOKEN`. The
  `--help` text shows a `localhost:9770` default for `--server`, but real
  builds ship with `https://es.sagecontinuum.org` baked in (the submit help
  on H00F showed the production default). Don't trust the help default —
  check the actual error/connection behavior.

## The pluginctl ≠ sesctl validation gap (root-cause gotcha)

Two different image-existence checks:

| Path | Checks against | Registers app? |
|------|----------------|----------------|
| `pluginctl deploy` | raw Docker registry `registry.sagecontinuum.org` (node-local k3s pull) | No |
| `sesctl submit` | **ECR app catalog** (registered-apps DB behind `portal.sagecontinuum.org/apps`) | No |

An image can be pullable from the Docker registry (so `pluginctl` runs it
fine, node-local) yet absent from the ECR app catalog. `sesctl submit` then
fails:

```
Returned "400 Bad Request": {
 "error": "[registry.sagecontinuum.org/<ns>/<plugin>:<ver> does not exist in ECR]"
}
```

An image lands in the ECR catalog ONLY after it's registered + built through
the ECR portal pipeline (My Apps → Create App → public GitHub repo URL →
sage.yaml + Dockerfile → build for target arch). Pushing/pulling the Docker
image, or deploying it with pluginctl, does NOT register it.

Confirmed: `birdnet-species:0.1.0` ran end-to-end via pluginctl on H00F, but
`sesctl submit -j 5645` returned the "does not exist in ECR" 400 because the
app was never built in the portal.

Key sub-detail: `sesctl create` SUCCEEDS even when the app isn't in ECR — it
just creates the job record (which waits). Only `submit` enforces ECR
existence. So a job ID can exist in a "created, never validated" state.

### Diagnose
- Sage MCP server `find_plugins_for_task` (or browse portal/apps) — if your
  plugin name isn't in the catalog list, it's not registered.

### Fix
1. Verify the repo is ECR-ready (Dockerfile + sage.yaml at repo root,
   `inputs` types only `string`/`int`, ecr-meta/ 6 files present).
2. Register + build in the ECR portal for the target arch (arm64 for Thor).
3. Re-run `sesctl submit -j <id>` — the pre-created job validates the moment
   the app exists in the catalog. If the original ID is stale, recreate:
   `sesctl create -f jobs/<job>.yaml` → note new ID → `submit -j <new-id>`.
