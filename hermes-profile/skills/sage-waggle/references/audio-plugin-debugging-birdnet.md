# Audio plugin debugging (BirdNET on network-camera mics)

Lessons from operating the birdnet-species plugin on Thor H00F, capturing
from a Reolink RLC-811A hummingcam over FLV/BCS. Applies to any Sage audio
plugin that records from a network camera and "runs cleanly but detects
nothing."

## 0. First move when "running but zero detections": LISTEN to the audio

A BirdNET pod can fire every tick, capture audio, exit 0, and detect ZERO
birds — and that is usually an AUDIO problem, not a model problem. Before
touching the model/threshold, grab a clip a human can actually hear. The
Reolink mic is faint, has NO input-gain control, and the sub-stream is only
16 kHz (Nyquist 8 kHz → higher harmonics of many calls are cut off).
BirdNET does NOT normalize input, so a quiet mic stays quiet to the model.

## 1. Grab-a-listen-clip workflow (matches what the model hears)

The capture MUST use the SAME ffmpeg path as the plugin's
`record_from_camera`, or you debug a different signal than BirdNET receives:
```
ffmpeg -y -i "$CAMERA_URL" -vn -acodec pcm_s16le -ar 48000 -ac 1 -t 60 out.wav
```
Then make an MP3 for playback/sharing (MP3 not WAV for shared assets, per
Pete's convention) and an OPTIONAL amplified MP3 for human listening only
(does NOT change what the model gets):
```
ffmpeg -y -i out.wav -codec:a libmp3lame -qscale:a 2 out.mp3
ffmpeg -y -i out.wav -filter:a "volume=20dB" -codec:a libmp3lame -qscale:a 2 out_amplified.mp3
```
A ready, parameterized script lives in the birdnet repo:
`tests/fetch-listen-clip.sh [DURATION_SEC] [GAIN_DB] [OUTNAME]` — probes the
stream, captures, emits wav+mp3 (+amplified), prints level stats, and tells
you the scp-back command. Defaults to 60s. There was previously only a
Mobotix-RTSP capture script (`tests/capture-audio.sh`, `rtsp://.../mobotix.sdp`)
— it does NOT work for the Reolink FLV/BCS camera; use the listen-clip script.

## 2. Reolink FLV/BCS auth + URL form (recurring gotcha)

Credentials MUST be query params, NOT HTTP basic auth:
```
http://CAMERA_IP:PORT/flv?port=1935&app=bcs&stream=channel0_sub.bcs&user=sage&password=CAMERA_PASSWORD
```
`http://user:pass@ip/...` returns ffmpeg "End of file"/exit 187. The job
uses the SUB-stream (16 kHz audio) → pair with `--bandpass-fmax 8000`.

## 3. Read the level stats with volumedetect

```
ffmpeg -i out.wav -af volumedetect -f null /dev/null 2>&1 | grep -E "mean_volume|max_volume"
```
Observed on the live hummingcam: `mean_volume: -27.8 dB`, `max_volume: 0.0 dB`.
Interpretation:
- `max_volume: 0.0 dB` = signal touching digital full-scale → possible
  clipping / DC offset / transient spikes (a yellow flag worth a longer,
  quieter-period capture to characterize).
- `mean_volume: -27.8 dB` with 0 dB peaks = mostly quiet with occasional
  spikes — consistent with a faint mic catching wind/handling noise but
  little sustained song. Supports "audio level, not model" as the cause.

This mean/max measurement is also the first concrete input to the parked
`--gain` work: the camera exposes no mic gain, so downstream gain in
`record_from_camera` is the only lever, and BirdNET won't normalize — so a
fixed-gain dB value must be chosen from measured levels (and validated by
listening) before wiring a `--gain` CLI option.

## 4. "No node manifest found — geo-filtering disabled"

Seen in birdnet pod logs: lat/lon auto-detect failed, so eBird seasonal
filtering is OFF and birds match against the global list instead of the
node's region/season. Not fatal (it still classifies) but reduces accuracy;
worth resolving for deployments where seasonal expectation matters.
