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

## 3. `sesctl rm` takes JOB_ID positionally; `submit` uses `-j`

Inconsistent flags across subcommands — easy to trip on:
- `sesctl submit -j <JOB_ID>`        (flag)
- `sesctl rm [-f|--force] <JOB_ID>`  (POSITIONAL; `rm -j 5669` → "unknown shorthand flag: 'j'")
- `sesctl rm -s <JOB_ID>`            (suspend, also positional)

`sesctl rm --help` confirms: `Usage: sesctl rm [FLAGS] JOB_ID [flags]`.

### Safe version-cutover pattern (verified repeatedly)
1. `sesctl rm -s <OLD_ID>`              # suspend old (keeps it as rollback, no delete)
2. `sesctl create -f jobs/<job>.yaml`  # returns a NEW numeric job id
3. `sesctl submit -j <NEW_ID>`         # start it
4. Verify the new version in the DATA PLANE (meta.plugin tag = new version) before
   trusting it. "Submitted"/"Running" is NOT proof.
5. Once confirmed live, `sesctl rm --force <OLD_ID>` to clean up the rollback.

A fresh `create+submit` does NOT force an immediate run for cron/`schedule()`-gated
jobs — it waits for the next tick (e.g. a `0 * * * *` window submitted at :53 first
runs at the next :00). Don't read the gap as a failure.

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
