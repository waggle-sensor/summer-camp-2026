# Publish-vs-Save pattern + Sage portal media rendering

Lessons from the bioclip/birdnet/yolo `--save-match` work (2026-06-24).

## 1. Decouple PUBLISH (always) from SAVE (selective)

For any detection plugin that uploads media (images/audio/video), separate two
concerns that are usually conflated:

- **Publish** measurement topics + a per-cycle **heartbeat** EVERY cycle, even
  when nothing is detected. The heartbeat is what lets the data plane prove the
  job is alive vs. dead. Topics: bioclip `env.species.summary`, birdnet
  `env.detection.audio.summary`, yolo `env.count.total`. Value carries e.g.
  `{"published_count":0,"top_confidence":0.11}` so a quiet cycle is diagnosable.
- **Save** (upload) media only when a detection matches a user rule. Uploading a
  blob is the expensive part (bandwidth + storage); publishing a number is cheap.

### `--save-match` grammar (shared `save_match.py`, identical copy per repo)
- Comma-separated OR-list of `Name:confidence` rules, e.g.
  `"Northern Cardinal:0.5,Barn Owl:0.4"`.
- `Name` matched **case-insensitively + EXACTLY** against the published name
  (common OR scientific for bioclip/birdnet; COCO class for yolo). No substring.
- Wildcard `"*:0.5"` = save on ANY detection >= 0.5.
- Save fires if ANY (rule x detection) matches; the whole clip/frame is saved
  ONCE (not per detection). Upload meta carries top species/class + confidence.
- Omitting `--save-match` = save NOTHING (opt-in). Fail-fast parse at startup
  (`SystemExit(2)` on malformed rule / out-of-range confidence) — a typo'd rule
  that silently saves nothing would waste a whole deployment.
- Convention used: each job sets `*:<min-confidence>` so the new selective-save
  preserves the old "save whatever you detect" behavior; narrow later to target
  species/classes.

### CRITICAL heartbeat pitfall (birdnet 0.1.x bug, fixed 0.2.0)
The summary/heartbeat publish was correct INSIDE `publish_detections()` (it always
emits the summary), BUT the CALL was gated behind `if detections:` in the run
loop. So quiet cycles published nothing — a live job looked dead. Fix: call the
publish unconditionally (gate only on `plugin is not None` for dry-run). When
auditing "is the heartbeat always-on?", check the CALL SITE, not just the function.
Confirmed live: telemetry (`plugin.duration.*`) kept publishing every cycle while
the summary heartbeat was absent on quiet cycles — that mismatch is the tell.

## 2. Sage portal (sage-gui) renders inline media by FILE EXTENSION

The portal frontend is `sagecontinuum/sage-gui` (TypeScript). The query-browser
view (`apps/sage/data-stream/QueryBrowser.tsx`) decides inline rendering by the
upload URL's extension, NOT by HTTP Content-Type:

- Images: rendered inline (`.jpg` etc.) — this is why annotated frames show up.
- Audio: **ONLY `.flac`** is inlined. Source proof:
  - `audio: ['.flac']`  (the extension map)
  - `else if (val.includes('.flac')) { <Audio dataURL={val}/> }`
  - `.wav` and `.mp3` appear NOWHERE in the frontend → they fall through to a
    plain download link, no inline player.

**Implication:** to get an inline audio player in the portal (like the
`seanshahkarami/audio-sampler` plugin, which uploads `.flac`), the plugin MUST
upload `.flac`. WAV/MP3 will not inline regardless of how playable they are in a
browser. Verify other media types the same way — read the extension map in
QueryBrowser.tsx rather than assuming Content-Type sniffing.

### FLAC is the right archival audio format for Sage
Switching a WAV-saving audio plugin to FLAC converges four wins at once:
1. inlines in the portal (matches the audio-sampler de-facto standard);
2. lossless — zero analysis-quality loss vs WAV (BirdNET keys on spectral shape);
3. ~50-70% smaller than uncompressed PCM WAV (e.g. 2.88 MB → ~1-1.4 MB);
4. NARA-preferred digital-audio archival format.
ffmpeg change: `-acodec flac` + `.flac` output. If the inference lib needs PCM,
decouple: transient WAV for analysis, FLAC for the archive upload.

### Audio size math (uncompressed PCM WAV)
`bytes = duration_s × sample_rate × channels × 2 (s16le) + 44 (header)`.
30 s mono 48 kHz = 2.88 MB. Beware up-sampling: if the camera sub-stream is only
16 kHz (Reolink BCS), a 48 kHz WAV stores 3× the bytes for zero extra signal
(real bandwidth capped at the 8 kHz Nyquist). Match `--sample-rate` to the source.

## 3. Deploy + VERIFY discipline (proven this session)
- Cutover = SUSPEND old job (`sesctl rm -s <id>`, keeps it as one-command
  rollback) → `create -f` new YAML → `submit -j <newid>`. Keep the old job
  SUSPENDED (not removed) until the new version is CONFIRMED publishing.
- "Submitted"/"Running" is NOT proof. Verify in the DATA PLANE: correct
  `meta.plugin` tag, heartbeat every cycle (negative path), AND a real
  detection→save (positive path). For vision plugins the positive path may be an
  ENVIRONMENTAL wait (e.g. bioclip needs daylight to clear a 0.7 visual
  threshold — pre-dawn max was 0.367; not a code failure). Distinguish
  "environmental quiet" from "broken" by checking detection HISTORY.
- Jobs fire on their cron tick: a fresh submit does NOT run immediately; it waits
  for the next schedule mark (e.g. `0 * * * *` submitted at :53 → first run :00).
- Node repo sync before build: gentle `git fetch` + `git pull --ff-only` (NEVER
  `git reset --hard`). A local file-mode-only diff (100644→100755) blocks pull;
  `git checkout -- <file>` to drop the redundant mode change, then pull.
- Build/sideload of registry.sagecontinuum.org images triggers a security-scan
  approval each time — expected, approve and proceed.
