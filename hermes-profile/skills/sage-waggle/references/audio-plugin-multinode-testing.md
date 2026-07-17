# Testing an audio plugin across node classes (H00F camera vs W-series mic)

The same ECR image runs on very different node hardware with different audio
paths. Test both to prove portability. `pluginctl deploy` is the one-shot test
(no SES job, no token needed for the deploy itself).

## Node login methods (they differ by class)

- **Thor / H-series (H00F):** `ssh USER@node-<VSN>.sage` (has `.sage` suffix).
  Needs `sudo kubectl`. Camera-based audio.
- **W-series (W06C etc.):** OLD-STYLE login `ssh waggle@waggle-dev-node-w06c`
  (gateway, NO `.sage` suffix, lowercase vsn). Needs `sudo kubectl`. USB-mic audio
  via `wes-audio-server`.

## Audio source differs by node → plugin auto-selects

- H00F: Reolink hummingcam. Pass `--camera 'http://IP:PORT/flv?...&user=&password='`
  (query-param auth, NOT basic; wrap in single quotes for `!`/`&`/`?`). 16 kHz
  sub-stream → `--bandpass-fmax 8000`.
- W06C: NO `--camera` arg → birdnet auto-selects `source=microphone (USB)` via
  `wes-audio-server` (which must be Running in the `default` ns). Full 48 kHz —
  higher quality than the camera path. Log confirms `Recording ... at 48000 Hz`.

## Geo-filter is genuinely location-aware (good portability proof)

Pass the node's real coords (`--lat --lon` from the manifest `gps_lat/gps_lon`)
and the startup log prints `Geo filter: N species expected at this location/time`.
N differs by location: H00F (Lemont, IL ~41.7,-88.0) ≈124 species; W06C (Grand
Teton, WY ~43.9,-110.6) ≈164 species. Different N = the eBird filter really keys
off coordinates. Absent that log line → filtering OFF (global species list).

## W-series scheduling gotcha: pods land on RPi children

A W-series "node" is a cluster (Xavier NX core + RPi children). `pluginctl` may
schedule the pod onto a `ws-rpi` child. First image pull there is SLOW (~830 MB,
observed 6m35s). During the pull the pod sits `Pending`/`PodInitializing` — this
is a slow pull, NOT a failure (check `kubectl describe pod ... | grep -A Events`;
look for `Pulling` then `Successfully pulled ... in Xm`). Don't kill it mid-pull.
After the image is cached, redeploy starts in seconds.

## Reading a successful run

Healthy log sequence: `source=` line → `Loading BirdNET V2.4 acoustic model` →
`Geo filter: N species` → `Recording 30 seconds ... at 48000 Hz` → `Audio saved
to /tmp/.../recording.flac (FLAC)` → `Classified ...: K detections in Ts`.
`0 detections above threshold` in a quiet window is a correct result, not a bug.
Harmless warning to ignore: `cv2 module not found` (pywaggle image shim; irrelevant
to audio — silence it by adding opencv-python-headless if tidy logs are wanted).

Always `sudo pluginctl rm <name>` to clean up the one-shot test pod when done.

## Is an SES plugin a persistent loop or a cycling one-shot? (lifecycle diagnosis)

To answer "does this job run continuously or fire/exit each cycle?" — DO NOT trust
a single `kubectl get pods` snapshot. The pod name is `<plugin>-<jobid>` where the
suffix is the JOB id (stable), so a one-shot's pods are REUSED-name and a snapshot
mid-run shows `Running` with a large AGE (e.g. `21d`) — which falsely looks
persistent. It's just whichever cycle happened to be running when you looked.

Decisive method — watch one full lifecycle live:

    # poll every 5s for ~2 min, timestamp each state
    for i in $(seq 1 24); do
      ts=$(date +%H:%M:%S)
      sudo kubectl get pods -n ses 2>/dev/null | grep -i <plugin> | sed "s/^/[$ts] /"
      sleep 5
    done

A cycling one-shot shows the arc: `PodInitializing` → `Running` → `Completed`
(observed: avian-diversity-monitoring on W06C, cron `* * * * *`, ~46s total per
cycle: ~5s init + ~38s run incl. a 20s capture, then Completed, gap until next
minute). Confirm cadence + capture length from the job spec (`sesctl stat -j <id>
-o /tmp/x.txt` — the summary `stat` alone omits args; `-o <file>` dumps full JSON
with `plugin_spec.args`, `science_rules` cron, `success_criteria`, and `user`).
A truly persistent plugin instead stays `Running` with restarts=0 across many
consecutive polls and logs repeated internal capture cycles from ONE pod.

Note `sesctl stat -j <id>` also works for a REMOVED job (shows Submitted/Started/
Completed timestamps + owner). Check `user`: a job may belong to someone else
(e.g. `gojian`'s "Testing-BirdNet" running the old avian plugin) — retiring/
replacing another user's job is a coordination step, not a unilateral one.

## Drafting a W-series mic replacement job (birdnet vs old avian)

When replacing the old `avian-diversity-monitoring` with birdnet on a mic node,
base the YAML on the proven sibling (`jobs/birdnet-reolink.yaml`) and adapt: NO
`--camera` (mic auto-select), NO `--bandpass-fmax` (mic is full 48 kHz; the 8000
cap is only for the 16 kHz camera substream), add explicit `--lat/--lon` (the old
avian job passed none → no geo-filter). Validate offline before submit: YAML
parses + has all SES keys (`name/plugins/nodes/scienceRules/successcriteria`) +
top-level key set matches the running sibling. Cadence caveat: birdnet cold-loads
the geo model (~13s) every one-shot, so per-minute cron wastes most of the cycle
on model load — prefer `*/2` unless exact behavioral parity with the old job is
required. (`make test`/`make build` do NOT cover job YAMLs — they verify the
plugin code + image; parse-and-parity is the right check for a spec file.)
