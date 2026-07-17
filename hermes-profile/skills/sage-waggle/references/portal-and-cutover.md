# Portal media inlining, query-browser quirks, sesctl job cutover, cloud-trigger watchers

Session-discovered durable platform behaviors (2026-06-24, H00F hummingcam work).

## 1. The portal query-browser inlines audio ONLY for `.flac`

The Sage portal frontend is `sagecontinuum/sage-gui` (TypeScript). The
query-browser at `apps/sage/data-stream/QueryBrowser.tsx` decides whether to
render an inline media player by FILE EXTENSION:

```ts
// QueryBrowser.tsx
audio: ['.flac']                      // the ONLY audio extension recognized
...
} else if (val.includes('.flac')) {
    <Audio dataURL={val}/>            // inline <audio> player rendered only for .flac
```

- `.wav` and `.mp3` appear NOWHERE in the frontend → those uploads show as a
  plain download link, NOT an inline player. Images (`.jpg`) inline via the image
  branch as usual.
- The reference `seanshahkarami/audio-sampler` plugin inlines because it uploads
  `.flac`.

IMPLICATION FOR AUDIO PLUGINS (birdnet etc.): save uploaded audio clips as FLAC,
not WAV/MP3. FLAC is a triple win:
  - inlines in the portal (the only reason it plays),
  - lossless → no quality loss for downstream model analysis (librosa/soundfile
    read FLAC natively; confirmed `soundfile.available_formats()` includes FLAC),
  - ~50-70% smaller than PCM WAV. Live-measured: a 30s 48kHz mono clip dropped
    from ~2.88 MB (WAV) to ~1.25 MB (FLAC); a 10s clip 960,078 B → 417,447 B.

ffmpeg change is one line: `-acodec flac` and a `.flac` output path (replacing
`-acodec pcm_s16le` / `.wav`). pywaggle `AudioSample.save("x.flac")` picks FLAC
by extension. No decouple needed — capture FLAC, analyze FLAC, upload FLAC.

ffmpeg-in-heredoc gotcha: `ffmpeg -i <url>` reads stdin and will EAT the rest of
a `bash -s <<'EOF'` script (interactive prompt). Add `-nostdin` (and/or
`</dev/null` per command) when running ffmpeg inside an SSH heredoc.

## 2. Query-browser filters by EXACT plugin version tag

The `apps=` URL param matches the full `registry.../ns/name:VERSION` string. After
a version cutover (e.g. 0.2.0 → 0.2.1) a URL still pointing at the OLD tag shows
the OLD records and "nothing new" — looks like the plugin stopped, but it's just
the filter. Fix: point `apps=` at the new version or use a wildcard
(`...name:0.2.1.*` or `...name.*`). Times in the URL are UTC. Namespace matters:
`beckman/...` not `sage/...`.

## 3. `sesctl rm` takes JOB_ID positionally; `submit`/`create` use flags

Global flags on EVERY subcommand (no env-var pickup — pass them explicitly; the
default `--server` is `localhost:9770`, so omitting it silently hits localhost):
- `--server https://es.sagecontinuum.org --token <SES_USER_TOKEN>`

Per-subcommand (inconsistent — easy to trip on):
- `sesctl create -f jobs/<job>.yaml`  (`-f`/`--file-path`; returns `{"job_id","state":"Created"}`)
- `sesctl submit -j <JOB_ID>`        (flag; `--dry-run` to validate without committing)
- `sesctl stat` / `sesctl stat -j <JOB_ID>`  (all-jobs list / one job)
- `sesctl rm [-f|--force] <JOB_ID>`  (POSITIONAL; `rm -j 5669` → "unknown shorthand flag: 'j'")
- `sesctl rm -s <JOB_ID>`            (suspend, also positional)

`sesctl rm --help` confirms: `Usage: sesctl rm [FLAGS] JOB_ID [flags]`.

sesctl + the token live ON the node (H00F: `/usr/bin/sesctl`), NOT on the dev box.
Run the create/submit/stat/rm from the node over SSH. There is no `sesctl version`.

### ECR-registration gate (the "does not exist in ECR" 400)
`create` almost always succeeds (it just registers the job spec). `submit` is where
the scheduler VALIDATES the image against the ECR APP CATALOG (ecr.sagecontinuum.org)
— NOT the Docker registry. A `400 {"error":"[registry.../ns/name:tag does not exist
in ECR]"}` on submit means the app was never built/registered through the ECR portal
pipeline. Docker-registry pullable (so `pluginctl` works node-local) ≠ ECR-registered
(so `sesctl` cloud-schedules). Fix: Register+Build the app via the ECR portal from
its GitHub repo + `sage.yaml`. The job sits Created and submits fine once ECR has it.

### A "side-loaded" plugin may actually be a long-running SES job
Before assuming a running plugin is a manual `pluginctl` deploy, check `sesctl stat`
— it may be an SES job submitted weeks ago (image side-loaded into k3s back when ECR
was broken). Symptom: pod in the `ses` namespace with an SES-style name
(`<jobname>-<JOBID>`), `pluginctl ls` shows nothing. Retire it via the cutover below,
not by deleting a pod.

### Safe version-cutover pattern (verified repeatedly)
1. `sesctl rm -s <OLD_ID>`              # suspend old (keeps it as rollback, no delete)
2. `sesctl create -f jobs/<job>.yaml`  # returns a NEW numeric job id
3. `sesctl submit -j <NEW_ID>`         # start it
4. Verify the new version in the DATA PLANE before trusting it. "Submitted"/
   "Running" is NOT proof. The discriminator: every published record carries
   `meta.job = "<task>-<JOB_ID>"` (e.g. `birdnet-species-5678`). So when old and new
   run the SAME task/version, `meta.job` is the ONLY way to tell whose data is whose:
   ```
   curl -s -X POST https://data.sagecontinuum.org/api/v1/query \
     -H 'Content-Type: application/json' \
     -d '{"start":"-15m","filter":{"vsn":"H00F","name":"env.detection.audio.summary"}}' \
   | tail -3   # look for "job":"<task>-<NEW_ID>"
   ```
   For cron/`schedule()`-gated jobs, the new job's first records appear only at the
   NEXT tick — records right after cutover may still show the OLD job id (produced
   just before you suspended it). That lag is expected, not a failure.
5. Once confirmed live, `sesctl rm --force <OLD_ID>` to clean up the rollback.

A fresh `create+submit` does NOT force an immediate run for cron/`schedule()`-gated
jobs — it waits for the next tick (e.g. a `0 * * * *` window submitted at :53 first
runs at the next :00). Don't read the gap as a failure.

### After a platform BLOCKER is fixed, refresh the repo's deploy docs (don't leave stale workaround prose)
When a long-standing platform workaround is resolved (e.g. the ECR `/proc/acpi`
buildkit bug fixed → side-load no longer needed; verified 2026-07-10 by an actual
ECR build of birdnet v0.2.1, then an official SES job cutover 5671→5678), the repo's
deploy docs that describe the workaround as REQUIRED become actively misleading —
they'll steer the next person down a manual path that's no longer necessary. Do a
disciplined refresh as part of closing out the fix, not later:
- **Dated status banner** at the top of each deploy doc: what changed, the date,
  the now-primary path, and the current deployed state (job name/id, image tag).
  e.g. "Status (2026-07-10): built by ECR Register-and-Build, runs as SES job
  birdnet-reolink (:0.2.1); the /proc/acpi blocker is fixed — side-load no longer
  required."
- **Promote the now-working path to primary**; DEMOTE the workaround to a clearly
  labelled historical/fallback section. Collapse the long procedure into a
  `<details><summary>…</summary>…</details>` block so it's retained (for offline/
  air-gapped bring-up and provenance) without dominating the doc.
- **Bump every stale version tag** across ALL docs (grep for `:<old-ver>` and the
  bare `<name>:<old>`; use replace_all). Missed tags in test/DGX guides are the
  usual stragglers. Confirm zero remain: `grep -rn '<name>:0.1' --include=*.md`.
- **Sweep for stale CLAIMS but keep legitimate historical/explanatory mentions.**
  `grep -rniE 'QEMU|does not exist in ECR|cannot .*(push|build)|sideload.*required'`
  then EXCLUDE lines that are now inside historical/fallback context or that
  correctly explain current behavior (e.g. "make the app public or SES returns
  'does not exist in ECR'" is a correct current note, not a stale claim; a status
  banner saying the blocker "is fixed" is correct). Don't blindly delete matches.
- Update any cross-repo tracker (`Infra-problems-to-fix.md`): mark the item
  RESOLVED with the date + the verification of record (the successful build/job),
  keep the historical detail, and note "do NOT re-file."
- Leave a forward-looking note where a doc's CURRENT-but-soon-to-change advice
  lives (e.g. "explicit --lat/--lon required on SES today; the wes-nodeinfo change
  will remove this") so the next refresh has a breadcrumb.

## 4. Cloud-trigger watcher pattern + the YOLO-vs-BioCLIP recall gap

Sage "cloud trigger" = a watcher running OFF-node (laptop/server/systemd/cron) that
polls the public data API and acts (Slack/email/etc.). Refs: waggle-sensor
`wildfire-trigger-example`, `severe-weather-trigger-example`.

PITFALL — silent death: a watcher run in a bare tmux session dies on reboot /
terminal close and goes silent with no signal. Prefer a `systemd` user service
(auto-restart + survives reboot) or a Hermes cron job (no long-lived daemon to die;
polls every N min). Always include a heartbeat/liveness path so silence is visible.

PITFALL — trigger-topic recall gap: a YOLO object-counter (`env.count.bird`) and a
whole-image BioCLIP classifier (`env.species.species`) detect VERY different
populations of the same scene. Live H00F 24h: `env.count.bird` = 15 detections vs
BioCLIP confident species = 156. YOLO misses small/fast subjects (hummingbirds)
that the whole-image classifier nails. A watcher keyed only on YOLO bird-count
misses ~90% of what's actually there. Fix: add an independent BioCLIP-species
trigger path (threshold on `env.species.species` confidence + a genus/species
allow-list to suppress night-time false positives), keeping the YOLO path too;
share cooldown + dedup-by-timestamp across both.
