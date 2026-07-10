# Shipping a plugin version: doc surfaces + the ECR "import" step

Pete's hard rule, reinforced repeatedly: a plugin version is NOT "done" until
**code + version + ALL doc surfaces ship in the SAME commit**. Splitting them
across commits is a defect. Bump together:

- `app.py` (the change)
- `sage.yaml` `version:`
- the job YAML `image:` tag (e.g. `jobs/<plugin>-<node>.yaml`)
- **every prose doc**: README, the job-YAML header comments,
  `ecr-meta/ecr-science-description.md`, and a per-plugin `CHANGELOG.md`.

## CHANGELOG.md — keep one per plugin

Each plugin repo gets a `CHANGELOG.md` (birdnet, sage-yolo, sage-bioclip all
have one as of 2026-06-23). Newest version first; group as Added/Changed/Fixed.
Always include a short "deployment note" footer for arm64/Thor plugins
(build-locally + sideload + catalog-register; SES uses
`imagePullPolicy=IfNotPresent`). For data-behavior fixes (geo-filter, publish
crash), add a "historical data" note: records carry the exact image version in
their `meta.plugin` tag, so the archive can be partitioned/filtered by version;
historical records are retained, not deleted (Pete's call).

## The ECR catalog "import" step — the one users miss

Document this prominently in DEPLOY / ecr-meta docs. SES validates a job's image
against the ECR app **catalog** (`ecr.sagecontinuum.org`), NOT the Docker
registry and NOT the sideloaded k3s image. Missing catalog record →
`[registry.../<ns>/<name>:<ver> does not exist in ECR]` on submit.

Workflow that actually works on Thor/arm64 (portal build crashes under QEMU):
1. **Build** locally, tagged with the FULL registry path:
   `sudo docker build -t registry.sagecontinuum.org/<ns>/<name>:<ver> .`
2. **Register catalog metadata** via `scripts/register-ecr-version.py`
   (clones a prior version's record, bumps version + git source, POSTs to
   `/api/submit` with `Authorization: Sage <portal-token>`).
3. **Sideload** the image into the node's containerd:
   `sudo docker save <full-tag> | sudo k3s ctr images import -`
   (works because pods use `imagePullPolicy=IfNotPresent`).
4. **Create + submit**: `sesctl ... create -f <job.yaml>` → returns numeric id;
   `sesctl ... submit -j <id>`.

## sesctl flag gotchas (the portal docs are WRONG)

- `create` uses `-f` / `--file-path` (NOT `--from-file`) and returns a numeric
  `job_id`.
- `submit` takes `-j <numeric-job-id>` (NOT the job *name*).
- `rm -s <id>` suspends; `rm <id>` removes.
- `stat` lists jobs with ids.

## Correct docs that claim auto-magic SES doesn't do

Stale docs often imply "the same job YAML works on any node" via manifest
auto-detection. FALSE on SES today: SES does NOT mount the node manifest into
plugin pods, and fixed nodes have no `sys.gps.*` publisher, so geo-location
auto-resolution yields nothing — fixed nodes need explicit `--lat/--lon` in the
job YAML. Fix these claims when you touch the doc.

## Common cleanups when syncing stale docs

- Stale defaults in arg tables (e.g. min-confidence/bandpass) — but check the
  CODE default vs the JOB override; the table documents the code default.
- Duplicate/renumbered step headings after inserting new steps (e.g. two
  "Step 4"s) — renumber the whole sequence.
- Old image tags hardcoded in example commands.

## Parallelizing the doc work

The mechanical per-plugin ecr-science-description sync (add a flag + a prose
section, match existing tone) parallelizes well via `delegate_task` with the
`file` toolset only — give each subagent the exact file path, the precise
change, the actual code defaults to cite, and "do not git commit, print a diff."
Keep the nuanced repo (the one with the subtle behavior story) for yourself.
