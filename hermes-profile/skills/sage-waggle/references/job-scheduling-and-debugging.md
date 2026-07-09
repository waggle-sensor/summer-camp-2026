# Sage Job Scheduling & Debugging — hard-won detail

Companion to the "Container Runtime & Scheduling Model" section in SKILL.md.
Everything here was verified on a live SGT/Thor node (H00F) during real
deployments. Prefer the job spec / data API as ground truth over guesses.

## One-shot cron is the norm; continuous pods are the exception

- The default Sage pattern is a **one-shot cron job**: scheduler fires a
  container, it captures → infers → publishes → exits in ~30-60s, every N min.
- A plugin running `--continuous Y --interval 60` deployed via
  `pluginctl deploy` is a **persistent pod** that loops internally and holds
  GPU/RAM continuously. This is almost always a leftover *test* deployment, not
  the right production shape. If the desired cadence is every N minutes, convert
  it to an SES cron job using the plugin's `--continuous N` (one-shot) flag.
- **Tradeoff — cold start:** one-shot reloads the model every cycle. Fine for
  small/TFLite/CPU models (BirdNET reloads in seconds). For large models
  (BioCLIP 2.5 ViT-H/14) measure the cold-start load time before committing to a
  tight schedule; if it's slow relative to the interval, keep that plugin
  continuous (hybrid: convert the light plugin, keep the heavy one warm).
- **avian-diversity-monitoring (the previous BirdNET) cron period is
  per-project, not fixed.** Observed across SES jobs: `*/5 * * * *` most common,
  `* * * * *` for dedicated "Avian"/"AvianPopUp" jobs, `*/20` for one standalone.
  Get a job's real cadence from its SES spec `scienceRules`, NOT from data
  timestamps (sparse per-species sampling distorts inter-record gaps).

## Namespace tells you how a pod was launched

- `ses` namespace  → launched by the **SES cloud scheduler** (cron/lambda job).
- `default` namespace → **hand-deployed** via `pluginctl deploy` (node-local).
- Commands: `sudo kubectl get pods -A | grep <name>` (shows namespace);
  `sudo pluginctl ps` (lists pods + uptime regardless of namespace).
- SES cron pods are short-lived and garbage-collected after they exit, so you
  often **cannot catch their logs** between ticks. Verify liveness via published
  DATA, not by racing to read the pod.

## pluginctl bypasses ECR; sesctl validates against it

- `pluginctl deploy` runs ANY local containerd image (e.g.
  `docker.io/library/<name>:<tag>` built on-node and k3s-imported). It does not
  check the ECR catalog. This is why a hand-deployed pod can run an image that
  SES would reject.
- `sesctl submit` validates the image against the **ECR app catalog** and fails
  with `{"error":"[<image> does not exist in ECR]"}` (HTTP 400) if the app isn't
  registered+built there.
- **An image being pullable from `registry.sagecontinuum.org/...` is NOT the
  same as the app being registered in the ECR catalog.** Pushing/pulling the
  Docker image alone does not register the app. Registration happens by building
  the app from its GitHub repo (sage.yaml + Dockerfile) via the ECR portal.
- Confirm registration:
  - Portal: `portal.sagecontinuum.org/apps/app/<namespace>/<app-slug>` — check
    the "Tagged Versions" tab shows a built version.
  - ECR API (anonymous): `https://ecr.sagecontinuum.org/api/apps/<ns>/<app>`
    returns `{"data":[{...,"id":"<ns>/<app>:<ver>", "source":{...}}]}`.
  - **Private app caveat:** if the app page exists but the public API returns
    `"data":[]` and the versioned endpoint
    `.../api/apps/<ns>/<app>/<ver>` returns **401** (not 404), the app is
    registered but PRIVATE. 401-vs-404 is the tell. Making it public via the
    portal exposes the version record to the anonymous API.
  - Note: the `find_plugins_for_task` MCP tool does not reliably surface a
    user's own namespace apps — trust the portal/API over it.

## "Scheduled but publishes nothing" — the heartbeat fix

Symptom: cron job fires every tick (pod appears in `ses` ns) but the data API
shows ZERO records — not even a summary. Almost always the plugin guards its
summary publish behind a positive result:

```python
if detections:            # <-- BUG: quiet cycles publish nothing
    plugin.publish("env.detection.audio.summary", ...)
```

Fix in the plugin: **always publish a per-cycle summary/heartbeat**, even on a
quiet cycle (`total_detections: 0`, empty species list). The per-species publish
loop above it naturally does nothing when the list is empty.

```python
# per-species loop is naturally a no-op when empty; summary ALWAYS publishes
plugin.publish("env.detection.audio.summary", json.dumps(summary), timestamp=ts)
```

This gives the data API a proof-of-life record every cycle, so you can tell
"running fine, nothing seen" from "job dead". Matches the convention of other
Sage plugins. (Code change → ECR rebuild + version bump to take effect.)

## sesctl operational gotchas (verified on-node)

- **Flags (the website docs are WRONG):**
  - create: `sesctl create -f|--file-path FILE` (docs say `--from-file` → fails
    `unknown flag: --from-file`).
  - submit/stat/rm: operate on a **numeric job ID** via `-j|--job-id` (docs imply
    by-name). `submit -j <id>`, `stat -j <id>`, `rm <id>` (JOB_ID positional for rm).
  - `--server` is the SES_HOST equivalent (default `http://localhost:9770`), so
    export `SES_HOST=https://es.sagecontinuum.org` or pass `--server` explicitly.
  - Wrong source: sagecontinuum.org/docs/reference-guides/sesctl and the
    edge-scheduler README. (TODO: file a docs PR via the page's "Edit this page".)
- **Removing a running job:** a RUNNING job cannot be removed directly →
  `Failed to remove ... as it is in running state. Suspend it first or specify
  force=true`. Sequence: `rm -s <id>` (suspend) then `rm <id>` (remove); or
  `rm -f <id>` to force. `rm -s` = suspend, `rm` = remove (same subcommand).
- **Token scope ≠ syntax:** a read-scoped token works for `stat` (read) but
  returns `401 "Invalid token"` on `rm`/`submit` (write) with the IDENTICAL
  command. If reads pass but writes 401, you need a scheduling/write-scoped token
  from portal.sagecontinuum.org/account/access — it's not a command error.
- The MCP server host may not have `sesctl` installed; nodes (H00F) do, at
  `/usr/bin/sesctl`. The node also needs the token in-env (it's typically only in
  the interactive shell, not in `~/.bashrc`, so non-interactive SSH can't see it).

## Reolink camera (RLC-811A) — auth, audio, gain

- **Auth:** BCS/FLV stream AND the CGI snapshot endpoint reject HTTP basic auth
  (`http://user:pass@ip/...`) → ffmpeg `End of file` / exit 187. Credentials MUST
  be QUERY PARAMS: `...&user=USER&password=PASS`. Single-quote the whole URL in
  shell to protect `!` (history expansion), `&`, `?`.
  - Working FLV (audio): `http://IP:PORT/flv?port=1935&app=bcs&stream=channel0_sub.bcs&user=CAMERA_USER&password=CAMERA_PASSWORD`
  - Working snapshot (image): `http://IP:PORT/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=snap&user=CAMERA_USER&password=CAMERA_PASSWORD&width=640&height=360`
- **Contrast — Mobotix M16:** MxPEG stream DOES use HTTP basic auth
  (`http://user:pass@ip/control/faststream.jpg?stream=MxPEG&needlength`).
- **No mic gain control:** Reolink's web UI "Audio" page has only Record-Audio
  on/off and a "Volume" that is SPEAKER output (two-way talk), NOT mic input
  gain. There is no AGC/sensitivity setting (unlike Mobotix M16). To boost faint
  audio you must apply downstream gain in the capture pipeline.
- **BirdNET does NOT normalize input amplitude** (verified in BirdNET-Analyzer
  audio.py: librosa load preserves levels; `smart_crop_signal` ranks segments by
  RMS energy but doesn't rescale; the `sensitivity` param shapes output logits,
  not input). So faint audio genuinely sounds quiet.
- **BUT downstream GAIN does NOT improve BirdNET detection — PROVEN, do not
  build it.** (Updated 2026-06-22, supersedes the earlier "apply measured fixed
  gain" advice.) Tested the same captured clip vs a +20 dB amplified copy
  through BirdNET: confidence was identical within ±0.01 (House Sparrow 0.3977 vs
  0.3947). BirdNET classifies on the time–frequency PATTERN, not absolute
  loudness, so uniform amplitude scaling adds no information. A `--gain` plugin
  feature is a DEAD END for detection. Gain is useful ONLY for HUMAN listening
  (keep it in the listen-clip tool, never as a detection lever). The real levers
  are: lower `--min-confidence` (the model already hears the bird — see
  `references/birdnet-audio-debugging-and-geofilter.md`), use a higher-bandwidth
  audio stream (the 16 kHz sub-stream's 8 kHz Nyquist clips upper harmonics), and
  enable geo-filtering. The `--gain` task on the backlog was CANCELLED for this
  reason.

## ECR sage.yaml input types — float may now work

Convention/docs say only `string` and `int` are supported (not `float`/`bool`),
and declaring floats as `string` (parsed in argparse) is the safe/portable
choice. BUT observed a published build (yolo-object-counter 0.2.0) with
`type: "float"` inputs (`conf-thres`, `iou-thres`) that ECR accepted. So float
may now be tolerated. If a build fails validation on a float input, fall back to
`string`; otherwise either works.
