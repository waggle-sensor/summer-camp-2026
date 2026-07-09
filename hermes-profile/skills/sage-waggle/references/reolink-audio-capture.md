# Reolink Camera Audio Capture for BirdNET

## Audio via HTTP FLV Stream (No RTSP Port Needed)

When only the HTTP port is mapped (e.g. port 80 mapped to 10000), use the
Reolink FLV stream endpoint to capture audio. No RTSP port mapping needed.

### Sub-stream (recommended — minimal bandwidth)

```bash
ffmpeg -i "http://USER:PASS@CAMERA_IP:HTTP_PORT/flv?port=1935&app=bcs&stream=channel0_sub.bcs" \
  -vn -acodec pcm_s16le -ar 48000 -ac 1 -t 30 output.wav
```

Sub-stream is 640x360 H.264 (~500 kbps video) vs main stream 3840x2160 H.265
(~8-15 Mbps). Audio is identical. Since we discard the video anyway, always use
sub-stream to avoid wasting network bandwidth on Thor.

### Main stream (avoid — 4K video wastes bandwidth)

```bash
ffmpeg -i "http://USER:PASS@CAMERA_IP:HTTP_PORT/flv?port=1935&app=bcs&stream=channel0_main.bcs" \
  -vn -acodec pcm_s16le -ar 48000 -ac 1 -t 30 output.wav
```

### Audio Specs (RLC-811A)

- Native codec: AAC at **16 kHz** sample rate, mono
- Nyquist frequency: **8 kHz** (2x better than M16's 4 kHz)
- ffmpeg upsamples to 48 kHz if requested but no new information above 8 kHz
- Appropriate BirdNET setting: `--bandpass-fmax 8000`
- Built-in microphone with 2-way audio support

### Important: ffmpeg pulls full FLV (video + audio) from camera

Even with `-vn`, ffmpeg receives the complete FLV stream over the network,
then discards video locally. The bandwidth between camera and Thor is the same
regardless of output format. Use sub-stream to minimize this.

### BirdNET Plugin Camera Flag

```bash
python3 app.py \
  --camera "http://USER:PASS@CAMERA_IP:HTTP_PORT/flv?port=1935&app=bcs&stream=channel0_sub.bcs" \
  --duration 30 --min-confidence 0.60 --bandpass-fmax 8000
```

The `--camera` flag in app.py auto-detects stream type:
- Mobotix MxPEG: detected by "faststream" + "MxPEG" in URL → adds `-f mxg`
- RTSP: detected by `rtsp://` scheme → adds `-rtsp_transport tcp`
- HTTP FLV (Reolink): no special flags needed — ffmpeg handles it natively

### Troubleshooting: Silent Audio (No Background Noise)

If the captured WAV file has zero detections AND no audible background noise,
the camera microphone is likely disabled in the encoding settings.

```bash
# Check audio status (look for "audio": 0 or 1 in response)
curl -s "http://CAMERA_IP:HTTP_PORT/api.cgi?cmd=GetEnc&user=USER&password=PASS" \
  -d '[{"cmd":"GetEnc","action":0,"param":{"channel":0}}]'

# Enable audio
curl -s "http://CAMERA_IP:HTTP_PORT/api.cgi?cmd=SetEnc&user=USER&password=PASS" \
  -d '[{"cmd":"SetEnc","action":0,"param":{"Enc":{"channel":0,"audio":1}}}]'
```

This is a common gotcha — the FLV stream will contain an audio track header
even when the mic is disabled, so ffmpeg completes without error and produces
a valid WAV file. The file just contains silence. Always listen to the raw
capture before concluding "no bird detections" — if there's no ambient noise
at all, the mic is off.

### Network Port Discovery

Check available ports via Reolink HTTP API:
```bash
curl -s "http://CAMERA_IP:HTTP_PORT/api.cgi?cmd=GetNetPort&user=USER&password=PASS" \
  -d '[{"cmd":"GetNetPort","action":0,"param":{"channel":0}}]'
```

Returns: httpPort, httpsPort, rtspPort, rtmpPort, mediaPort, onvifPort with
enable flags. RTSP is typically on 554 but may not be port-mapped through
the router.

### Reolink Focus Control via HTTP API

Requires token-based auth (short-session user/password in URL may not work on
all models).

```bash
# Step 1: Get token
curl -s -k "http://CAMERA_IP:PORT/api.cgi?cmd=Login" \
  -d '[{"cmd":"Login","param":{"User":{"userName":"USER","password":"PASS"}}}]'

# Step 2: Set focus position (replace TOKEN)
curl -s -k "http://CAMERA_IP:PORT/api.cgi?cmd=StartZoomFocus&token=TOKEN" \
  -d '[{"cmd":"StartZoomFocus","action":0,"param":{"ZoomFocus":{"channel":0,"pos":3060,"op":"FocusPos"}}}]'

# Disable autofocus (lock manual focus)
curl -s -k "http://CAMERA_IP:PORT/api.cgi?cmd=SetAutoFocus&token=TOKEN" \
  -d '[{"cmd":"SetAutoFocus","action":0,"param":{"AutoFocus":{"channel":0,"disable":1}}}]'
```

StartZoomFocus `op` values: FocusPos, ZoomPos, FocusDec, FocusInc, ZoomDec, ZoomInc.

### Audio Quality Comparison

| Source | Native Rate | Nyquist | Notes |
|--------|------------|---------|-------|
| USB mic (ETS ML1-WS) | 48 kHz | 24 kHz | Best — full bandwidth |
| Reolink RLC-811A | 16 kHz | 8 kHz | Good — covers most passerines |
| Mobotix M16 | 8 kHz (pcm_alaw) | 4 kHz | Poor — misses high-frequency birdsong |

### Auth format: query params, NOT HTTP basic auth (CRITICAL)

The Reolink FLV/BCS endpoint does **NOT** accept HTTP basic auth (`user:pass@host`).
It expects credentials as **query parameters**. The basic-auth form makes ffmpeg
fail instantly with `Error opening input: End of file` / `exit 187`.

```bash
# WRONG — ffmpeg gets "End of file", exit 187:
--camera 'http://CAMERA_USER:CAMERA_PASSWORD@CAMERA_IP:PORT/flv?port=1935&app=bcs&stream=channel0_sub.bcs'

# CORRECT — credentials as query params:
--camera 'http://CAMERA_IP:PORT/flv?port=1935&app=bcs&stream=channel0_sub.bcs&user=CAMERA_USER&password=CAMERA_PASSWORD'
```

Confirmed working: 30s capture = 2,875,374 bytes (≈ 30s × 48000 × 2 bytes mono).
Always **single-quote** the URL in shell — the `!` in passwords like `CAMERA_PASSWORD`
triggers bash history expansion otherwise.

### Faint audio: gain compensation (BirdNET does NOT re-level)

**Key fact verified from BirdNET-Analyzer source (`audio.py`)**: BirdNET does
**not** normalize or re-level input amplitude. librosa loads samples in [-1,1]
but preserves whatever amplitude was in the file; the only amplitude-aware step
is `smart_crop_signal`, which uses RMS+peak energy to *rank/select* which 3-second
segments to keep — it does not scale them. The `sigmoid_sensitivity` parameter is
applied to the model's output logits (post-classification confidence shaping), NOT
to the input waveform — it cannot recover SNR that isn't there.

**Consequence**: faint recordings score low and BirdNET will not compensate. A
quiet mic (audible-but-faint chirps + background hiss) produces sub-threshold
confidences regardless of how many birds are calling. There is no risk of
"double-leveling" by pre-amplifying — there is no leveling to double up on.

**Recommended fix — measured FIXED gain (not dynaudnorm)**:
1. Measure headroom first so we don't clip:
   ```bash
   ffmpeg -i '<flv-url-with-query-auth>' -t 15 -vn -af volumedetect -f null - 2>&1 \
     | grep -E 'mean_volume|max_volume'
   ```
   If `mean_volume` ≤ ~-50 dB, the mic is effectively silent (or off — see silent-audio
   troubleshooting above). `-20` to `-35` dB means real audio, just a quiet window.
2. Apply a fixed gain with headroom (e.g. if `max_volume` is -30 dB, ~25 dB is safe):
   ```bash
   ffmpeg -i '<flv-url>' -t 30 -vn -af 'volume=25dB' -acodec pcm_s16le -ar 48000 -ac 1 out.wav
   ```

**Why fixed gain, not `dynaudnorm`/`loudnorm`**: fixed gain preserves the relative
dynamics within the clip (birds stay louder than background — the contrast BirdNET
relies on). `dynaudnorm`/`loudnorm` *compress* dynamic range: they pull up faint
chirps but also pull up the background hiss in quiet passages, hurting SNR and often
degrading BirdNET results. Use fixed gain for a faint-but-clean source.

**Caveat — possible hidden firmware AGC**: the RLC-811A may apply its own internal
AGC that isn't exposed. If so, a faint-but-clean signal means AGC is already maxed
and downstream gain amplifies the noise floor too. Still helps BirdNET (no input
normalization), just don't expect miracles — measure with `volumedetect` first.

### Reolink RLC-811A exposes NO mic input gain

Unlike the Mobotix M16 (which has a mic sensitivity/level control), the consumer-grade
RLC-811A web interface has only two audio settings under Camera → Audio:
- **Record Audio** — on/off toggle (enables/disables the mic, no level)
- **Volume** — this is the **speaker** output volume for two-way talk-back, NOT mic
  input gain (Reolink docs: "For cameras that have a speaker, the volume can be adjusted")

There is no input sensitivity, AGC toggle, or mic gain slider. Gain compensation must
happen downstream in the capture pipeline (see fixed-gain section above).
