# Camera Audio Capabilities for BirdNET

## Camera Comparison Table

| Camera | Built-in Mic | Audio Input | Max Sample Rate | Extra HW Needed | BirdNET Usable? |
|--------|-------------|-------------|-----------------|-----------------|-----------------|
| **Mobotix M16** | **Yes** | **Built-in** | **16 kHz (Opus) / 8 kHz (pcm_alaw)** | **Nothing** | Marginal (4 kHz ceiling) |
| XNV-8081Z (Hanwha) | No | Yes (on body) | 16 kHz (AAC-LC) | External mic | Yes with mic |
| AXIS Q6055-E | No | Yes (multicable) | 48 kHz (Opus) | Multicable + mic | Yes with accessories |
| XNP-6400RW (Hanwha) | No | No | N/A | SPM-4210 I/O Box + mic | No without I/O box |

## Mobotix M16 Audio Details

- Built-in microphone and speaker in camera body
- Native audio: **pcm_alaw at 8 kHz** (G.711 A-law)
- Nyquist limit: **4 kHz** — most bird songs are 1-8 kHz, so upper harmonics lost
- Does NOT serve RTSP (port 554 refused on tested units)
- Audio available via MxPEG HTTP stream:
  ```
  ffmpeg -f mxg -i "http://admin:pass@CAMERA_IP/control/faststream.jpg?stream=MxPEG&needlength" \
    -t 60 -vn -acodec pcm_s16le -ar 48000 -ac 1 recording.wav
  ```
- The `-f mxg` input format flag is required for MxPEG streams
- Tested M16: 130.202.23.119 (admin/wagglesage), H00F node

## BirdNET with Camera Audio

- BirdNET V2.4 expects 48 kHz input, uses frequencies up to ~15 kHz
- With 8 kHz source (M16): content only up to 4 kHz, model sees empty upper spectrogram
- Use `--bandpass-fmax 4000` to tell the model about the bandwidth limitation
- Use `--min-confidence 0.60` (higher threshold) to reduce false positives from degraded audio
- Test results from M16 at 0.10 threshold: all detections below 0.40, mostly false positives (wrong continent species)
- USB microphones (48 kHz) are significantly better for BirdNET than any camera mic

## XNV-8081Z Audio Details

- Audio input jack directly on camera body (no I/O box needed)
- Selectable mic-in or line-in, supply voltage 2.5VDC
- Max quality: AAC-LC at 16 kHz (8 kHz Nyquist)
- Audio detection and sound classification built-in
- RTSP: `rtsp://user:pass@CAMERA_IP:554/profile1/media.smp`

## AXIS Q6055-E Audio Details

- Audio input via multicable (sold separately)
- Supports Opus at 48 kHz — best audio quality of the cameras
- Mic-in and line mono input on multicable connector
- RTSP: `rtsp://user:pass@CAMERA_IP/axis-media/media.amp`
- End-of-support product (replaced by Q6086-E)

## XNP-6400RW Audio Details

- NO built-in microphone, NO audio input on camera
- Audio detection requires SPM-4210 Network I/O Box (separate purchase)
- The I/O box connects to camera via network, provides mic input
- Datasheet explicitly states: "Audio detection, Sound classification (with NW I/O Box)"

## USB Microphone (Recommended)

- ETS ML1-WS IP54: outdoor-rated, 48 kHz, used on W-series Wild Sage Nodes
- Full bandwidth for BirdNET — no bandpass filtering needed
- Connected directly to node via USB, accessed via pywaggle `Microphone` class
- No `--camera` flag needed — default plugin mode
- Significantly better detection accuracy than any camera mic

## Auto-Detection Features

The birdnet plugin auto-detects:
- **Location**: reads GPS from `/etc/waggle/node-manifest-v2.json` when `--lat`/`--lon` not specified
- **Season**: `--week auto` (default) calculates BirdNET week from current date
- **Stream type**: `--camera URL` auto-detects Mobotix MxPEG (adds `-f mxg`) vs RTSP (adds `-rtsp_transport tcp`)

This means the same job YAML works on any node without hard-coding location or season.
