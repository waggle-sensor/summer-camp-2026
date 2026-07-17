# Reolink HTTP Snapshot API

## When to use

When a Reolink camera is behind a router that only port-maps HTTP
(port 80) but not RTSP (port 554). The `--snapshot-url` flag in
sage-yolo fetches a JPEG each cycle via the CGI API instead of
using pywaggle's Camera class (which requires RTSP or a video stream).

## URL format

**Full resolution (main stream, e.g. 3840x2160 for RLC-811A):**
```
http://IP:PORT/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=<random>&user=<user>&password=<pass>
```

**Sub-stream resolution (640x360, recommended for inference):**
```
http://IP:PORT/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=<random>&user=<user>&password=<pass>&width=640&height=360
```

The `rs` parameter is required but can be any random string.

## Bandwidth comparison

| Resolution | Size per frame | Frames/hour (60s interval) | Hourly bandwidth |
|-----------|---------------|---------------------------|-----------------|
| 4K (3840x2160) | ~445 KB | 60 | ~26 MB |
| Sub (640x360) | ~12 KB | 60 | ~720 KB |

**38x bandwidth reduction** — critical for LTE-connected cameras.
YOLO resizes to 640px anyway, so full-res snapshots waste bandwidth
with zero accuracy benefit.

## Plugin usage

```bash
# One-shot test (--continuous N)
python3 app.py --snapshot-url "http://IP:PORT/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=snap&user=USER&password=CAMERA_PASSWORD=640&height=360" --continuous N

# Continuous via pluginctl (every 60 seconds)
sudo pluginctl deploy -n yolo-hummingcam \
    --resource 'memory=8Gi,limit.memory=16Gi' \
    docker.io/library/yolo-object-counter:0.2.0 \
    -- --snapshot-url "http://..." --interval 60 --continuous Y --upload-image Y
```

## Implementation

The `fetch_snapshot()` function in app.py:
1. `urllib.request.urlopen(url, timeout=15)` — fetches raw bytes
2. `np.frombuffer(img_bytes, dtype=np.uint8)` — wraps as numpy array
3. `cv2.imdecode(img_array, cv2.IMREAD_COLOR)` — decodes JPEG to BGR
4. Returns BGR numpy array, same format as Camera.snapshot().data

No pywaggle Camera dependency. Works with any HTTP URL returning JPEG.

## Verified cameras

- **Reolink RLC-811A** ("HummingCam01") on Thor node H00F
  - Router port-maps 10000→80 (HTTP only)
  - Tested with `&width=640&height=360` (12KB per frame)
  - IR night vision produces grayscale — YOLO still detects objects
  - Future: port-map 10001→554 for RTSP streaming

## Audio capture (FLV/BCS) — DIFFERENT auth from snapshots

For audio plugins (e.g. BirdNET) that pull the Reolink mic via ffmpeg, the
FLV/BCS endpoint does **NOT** accept HTTP basic auth (`http://user:pass@ip/...`).
Basic auth returns ffmpeg `Error opening input: End of file` / **exit 187**.
Credentials MUST be passed as **query parameters**:

```
http://IP:PORT/flv?port=1935&app=bcs&stream=channel0_sub.bcs&user=USER&password=CAMERA_PASSWORD
```

Confirmed working on H00F hummingcam (RLC-811A, sub-stream carries 16 kHz audio,
30s capture). Contrast with Mobotix M16 MxPEG, which DOES use inline basic auth
(`http://user:pass@ip/control/faststream.jpg?stream=MxPEG&needlength`).

**Shell escaping:** always wrap the `--camera` URL in **single quotes**. The
password often contains `!` (history expansion under double quotes), and `&`/`?`
are shell metacharacters.

**No mic input gain on RLC-811A:** the web UI Audio settings expose only
Record-Audio on/off and a *speaker* Volume (two-way talk-back) — there is NO mic
input gain/sensitivity control (unlike Mobotix M16). For faint audio the only
lever is downstream gain in the capture pipeline (ffmpeg `volume=NdB`). Measure
first with `ffmpeg -af volumedetect` to pick a value with headroom. Note BirdNET
does NOT normalize input amplitude (librosa load preserves levels; `sensitivity`
shapes output logits, not input), so a louder pre-amplified signal genuinely
helps detection — but prefer fixed gain over dynaudnorm/loudnorm to preserve the
bird-vs-background contrast.

## BirdNET V2.4 audio preprocessing (source: birdnet_analyzer/audio.py)

BirdNET does NOT normalize input amplitude at any stage:
1. `open_audio_file()` — librosa load at 48 kHz mono, preserves amplitude
2. Optional bandpass (fmin/fmax)
3. `split_signal()` — 3s chunks, pad with zeros/noise
4. Mel spectrogram → model

`smart_crop_signal()` uses RMS energy + peak (0.7/0.3 weights) to RANK
segments but does NOT scale them. The `sensitivity` parameter shapes output
logits (sigmoid), not input waveform. So faint recordings genuinely produce
lower confidence — pre-amplifying the capture is the standard remedy.

## Troubleshooting

**curl returns HTML instead of JPEG:**
  → Wrong URL path. Must be `/cgi-bin/api.cgi?cmd=Snap&...`, not `/`.

**"Could not decode image" error:**
  → Check credentials. Wrong user/password returns a JSON error, not JPEG.
  → Verify with: `curl -o test.jpg "URL" && file test.jpg`

**cv2.VideoCapture() can't open the URL:**
  → Expected. The CGI endpoint returns a single JPEG, not a video stream.
  → Use `--snapshot-url` flag, not `--stream`.
