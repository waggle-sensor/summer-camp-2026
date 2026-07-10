# Deploying arm64 plugins to Thor: ECR build reality + sideload workaround

Hard-won operational detail (June 2026) for getting a plugin scheduled on a
Thor (aarch64) Sage node when the normal ECR portal build path fails. Applies
to any NVIDIA-base GPU plugin; the registry-push half applies to ALL plugins.

## The two independent blockers

### Blocker 1 — ECR portal build crashes for arm64 NVIDIA-base plugins
The ECR/Jenkins build pipeline runs on **x86_64** and cross-builds `linux/arm64`
under **QEMU emulation**. The NVIDIA base image
(`nvcr.io/nvidia/pytorch:25.08-py3`) contains aarch64 binaries QEMU cannot
emulate. The build dies at the pip/torch step:

```
qemu: uncaught target signal 6 (Aborted) - core dumped
... did not complete successfully: exit code: 134
```

Removing `linux/amd64` from sage.yaml does NOT help — the problem is
arm64-via-QEMU-on-x86, not "building amd64 too". Only a **native arm64 build
node** in the pipeline fixes this. CPU-only plugins on `python:3.12-slim`
(e.g. birdnet) are NOT affected — they have native arm64 wheels and the portal
build succeeds.

### Blocker 2 — you cannot `docker push` to registry.sagecontinuum.org
A Sage portal access token authenticates (`docker login
registry.sagecontinuum.org -u <user>` with the token as password succeeds) but
is **read/pull-only**. Pushes fail:

```
denied: requested access to the resource is denied
```

Registry writes are reserved for the Jenkins pipeline. This blocks the obvious
"build natively on Thor, then push" idea — build works, push is denied.

## The working workaround: build locally + sideload into k3s

SES pods run with **`imagePullPolicy: IfNotPresent`**. So if a locally-cached
image exists in k3s containerd under the *exact registry-qualified name* the
job YAML references, the pod uses it and never pulls from the registry.

```bash
# 1. Build natively on Thor (aarch64, no QEMU), tagged with the FULL registry path
cd ~/AI-projects/<repo>
git pull
sudo docker build -t registry.sagecontinuum.org/<ns>/<app>:<ver> .

# 2. Sideload into k3s containerd (large images take minutes; bioclip ~28GB)
sudo docker save registry.sagecontinuum.org/<ns>/<app>:<ver> \
  | sudo k3s ctr images import -

# 3. Verify — must show io.cri-containerd.image=managed (means k8s/SES can see it)
sudo k3s ctr images ls | grep <app>
```

The tag MUST be the full `registry.sagecontinuum.org/<ns>/<app>:<ver>`, not a
bare `<app>:<ver>`. A bare-named local image (what the old `pluginctl deploy`
workflow used) will NOT be matched by the job's `image:` field.

Gotcha: the bare local image name can differ from the registry/app name. E.g.
local `bioclip-species` vs ECR app `bioclip-species-classifier`. Tag with the
registry/app name.

If after import the pod still ErrImagePulls, the image may have landed in the
wrong containerd namespace — force the k8s namespace:
`sudo docker save <tag> | sudo k3s ctr -n k8s.io images import -`
(In practice the default import already showed `io.cri-containerd.image=managed`
and worked — only reach for `-n k8s.io` if it doesn't.)

## App-catalog registration is still required (separate from the image)
SES validation checks the ECR **app catalog**, not the raw Docker registry.
So the app + version record must exist in the portal (My Apps → Create App from
the GitHub repo) even when you sideload the actual image. The portal *build*
will fail (QEMU) — that's fine, you only need the metadata registered. The app
must be **public** or SES returns `registry does not exist in ECR`.

This is a two-layer system, easy to confuse:
- ECR **app catalog** (metadata) → SES `create`/`submit` validation checks this
- Docker **registry** (the image bytes) → containerd pulls this at pod start
Both must be satisfied. Sideload satisfies the second locally.

## Verifying a scheduled job actually runs (it's invisible between ticks)
One-shot cron pods fire, run ~30-40s, exit, and get GC'd — so `kubectl get pods
-n ses` is usually empty. Don't conclude "not running" from an empty namespace.
Confirm via the data API and check the record metadata:

```bash
curl -s -X POST https://data.sagecontinuum.org/api/v1/query \
  -H 'Content-Type: application/json' \
  -d '{"start":"-15m","filter":{"vsn":"<VSN>","name":"<measurement>"}}'
```

Proof it's the SES job (not a leftover hand-deployed pod):
- `"job": "<app>-<jobid>"`  (a hand-deployed pod shows `"job": "Pluginctl"`)
- `"plugin": "registry.sagecontinuum.org/<ns>/<app>:<ver>"`  (hand-deployed
  shows `"plugin": "docker.io/library/<app>:<ver>"`)
Pod events showing `Container image "...:ver" already present on machine`
confirm the sideload was hit instead of a registry pull.

To catch a short-lived pod's image/policy/logs, poll in a loop and grab it the
instant it appears (it'll be gone in ~40s):
```bash
for i in $(seq 1 75); do
  POD=$(sudo kubectl get pods -n ses 2>/dev/null | grep -i <app> | awk '{print $1}' | head -1)
  [ -n "$POD" ] && { sudo kubectl get pod -n ses "$POD" -o jsonpath='{.spec.containers[0].imagePullPolicy}'; sudo kubectl logs -n ses "$POD"; break; }
  sleep 10
done
```
Or inspect pull failures after the fact: `sudo kubectl get events -n ses
--sort-by=.lastTimestamp` — ErrImagePull / "not found" shows the registry the
scheduler tried and failed to pull from.

## Continuous pod vs one-shot cron — which style and why
Most Sage plugins are one-shot cron (`schedule(...): cronjob(..., "*/10 * * * *")`)
— fire, process, publish, exit. A few run as long-lived `--continuous Y`
`pluginctl` pods in the `default` namespace (hand-deployed, NOT scheduler-
managed). Tells them apart: namespace `ses` = SES-scheduled; namespace
`default` + `job=Pluginctl` = hand-deployed.

- One-shot cron: frees GPU/RAM between runs, scheduler auto-restarts, survives
  reboot, Sage-native. Cost: cold-start model reload each cycle. Right for
  cadences ≥ a few minutes. Heavy models (e.g. BioCLIP 2.5 ViT-H/14) reload
  every tick — acceptable at */10, but measure load time before tightening.
- Continuous: model stays warm (low latency, high cadence) but pins GPU/RAM
  24/7, dies silently on crash, invisible to SES, not visible on the portal
  node page. Test-deployment style that shouldn't become production.

## Stopping/removing a running SES job (sesctl rm semantics)
`sesctl rm` refuses to remove a job in **Running** state. Suspend first, then
remove (flag goes before the positional JOB_ID):
```bash
sesctl --server https://es.sagecontinuum.org --token "$TOK" rm -s <jobid>   # suspend
sesctl --server https://es.sagecontinuum.org --token "$TOK" rm    <jobid>   # remove
sesctl --server https://es.sagecontinuum.org --token "$TOK" stat -j <jobid> # verify -> Removed
```
`-s`/`--suspend` suspends, no flag removes, `-f`/`--force` forces.

## Token scopes are NOT uniform
The same token string can pass read ops and fail write ops. A token that does
`sesctl stat` fine may 401 ("Invalid token") on `sesctl rm`/`rm -s`, and a
portal token that `docker login`s fine may be denied on `docker push`. When a
write op 401s but reads work, it's a scope problem, not a transmission/syntax
problem — use the credential that originally created/submitted the job.

## Documenting this workaround in the plugin repos (Pete's doc discipline)
When you deploy via sideload, FIX the per-repo docs in the SAME work — stale
docs that say "ECR pulls from GitHub and builds for you" are actively wrong for
Thor plugins and will mislead students. Required corrections:
- `DOCKER-BUILD.md`: replace any "Publish to Sage ECR (portal builds for you)"
  section with the real flow — why (QEMU build crash + push denied) and how
  (build native on Thor → tag full registry path → sideload → register app
  metadata → sesctl create/submit → verify via data API).
- Keep ONE path for students, not a "Path A portal / Path B sideload" fork.
  Pete's explicit rule: "one path for students, not two paths based on if
  something fails because they pull in a library." Even for the CPU-only
  plugin (birdnet) whose portal build *could* work, document the single
  sideload path so all plugins share one identical procedure (one thing to
  learn, no special case). Fold any base-image difference into a one-line note
  inside the "why", not a divergent path.
- Use identical section headings across all sibling plugin repos (Why → Step
  1–6 → Re-deploying → Systemic fix) so the docs are uniform.
- Job-YAML header comments: correct the sesctl syntax too (the website's
  `create --from-file` / submit-by-name is wrong; real binary uses `-f`,
  `submit -j <numeric-id>`, `stat -j`, `rm -s` to suspend). See
  references/sesctl-ecr-validation.md.
- Pete updates ALL doc surfaces in the same commit as the change (his standing
  rule). Commit code + version bump + docs together.

## Systemic fix to escalate (ECR/cyberinfra team)
The sideload workaround is manual and per-node. Durable fix is either:
- (a) grant push/write access to `registry.sagecontinuum.org/<ns>/` for a
  portal token, so `docker push` works after a native Thor build; or
- (b) add a native arm64 build node to the Jenkins ECR pipeline so the portal
  "Register and Build" path works without QEMU.
Either unblocks every Thor-targeted NVIDIA plugin and removes the manual step.
