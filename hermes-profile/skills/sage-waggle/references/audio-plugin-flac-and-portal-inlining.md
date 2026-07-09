# Audio plugins: save FLAC so the Sage portal inlines a player

## The rule
If a Sage plugin uploads an audio clip and you want it to render with an inline
`<audio>` player in the portal query-browser (the way images render inline),
**save the clip as `.flac`**. WAV and MP3 are NOT recognized for inline playback.

## Why (verified in source, 2026-06-24)
The portal frontend is `sagecontinuum/sage-gui` (TypeScript). In
`apps/sage/data-stream/QueryBrowser.tsx`:

```ts
// ~line 60
audio: ['.flac'],            // the ONLY audio extension the browser treats as inline-able
...
// ~line 97
} else if (val.includes('.flac')) {
    <Audio dataURL={val}/>   // inline player rendered ONLY when the upload URL contains .flac
}
```

`.wav` and `.mp3` appear NOWHERE in the frontend rendering logic, so an uploaded
`*.wav`/`*.mp3` falls through to a plain download link with no player. Sean
Shahkarami's `audio-sampler` plugin inlines precisely because it uploads `.flac`.

To confirm the gate yourself without a browser, use the GitHub CLI (the code
search API needs auth; `gh` already has it):
```
gh search code --repo sagecontinuum/sage-gui ".flac"   # hits QueryBrowser.tsx, beehive.ts
gh search code --repo sagecontinuum/sage-gui ".wav"    # ZERO hits
gh api repos/sagecontinuum/sage-gui/contents/apps/sage/data-stream/QueryBrowser.tsx \
  --jq .content | base64 -d | grep -niE "audio|\.flac|<Audio"
```

## FLAC is the right choice on the merits (not just for the portal)
- **Lossless** — identical spectral content to PCM/WAV, so BirdNET (and any
  librosa/soundfile consumer) detect exactly the same. No quality tradeoff.
- **~50-70% smaller than WAV.** Measured live on the H00F Reolink sub-stream:
  a 10 s 48 kHz mono clip was 417,447 B FLAC vs 960,078 B WAV (FLAC = 43% of WAV,
  i.e. 57% smaller). A 30 s clip drops from ~2.88 MB to ~1.25 MB.
- **Recognized archival format** (NARA preferred for digital audio) — good for the
  Beehive long-term archive.
- It simultaneously solves three concerns: portal inlining, storage size, and
  archival fidelity. Prefer it over "downsample the WAV to the camera's true rate"
  or "passthrough the camera's native AAC".

## How to implement (birdnet pattern, generalizes to any audio plugin)
BirdNET reads audio by *path* via `model.predict(audio_path, ...)`, and the
`birdnet` PyPI lib decodes through librosa/soundfile, which support FLAC
natively. So you can go ALL-FLAC — capture FLAC, analyze the FLAC, upload the
FLAC. No need to keep a separate WAV "analysis copy".

Camera capture (ffmpeg) — change the codec and the extension:
```python
flac_path = os.path.join(tmpdir, "camera_audio.flac")
cmd = ["ffmpeg", "-nostdin", "-y", *input_args, "-i", url,
       "-vn",
       "-acodec", "flac",        # was pcm_s16le -> .wav
       "-ar", str(sample_rate),
       "-ac", "1",
       "-t", str(duration_s),
       flac_path]
```
USB mic path (pywaggle): just name the file `recording.flac` — pywaggle's
`AudioSample.save()` selects the container from the extension via soundfile.

The rest of the plugin (upload_file, save-match, CSV) is format-agnostic if it
references a generic `audio_path` variable — no other changes needed.

## Verify the library can read FLAC before committing to all-FLAC
Run inside the plugin image:
```
sudo docker run --rm --entrypoint python3 <image> -c \
  "import soundfile as sf; print('FLAC' in sf.available_formats()); import librosa; print(librosa.__version__)"
```
Expect `True` + a librosa version. If a library can't read FLAC, fall back to the
decouple pattern: transient WAV for analysis, FLAC for the archive upload.

## ffmpeg-in-heredoc pitfall
When running `ffmpeg` inside an `ssh ... 'bash -s' <<'REMOTE'` heredoc, ffmpeg
reads its interactive command prompt from stdin and swallows the rest of the
script ("Enter command: ... syntax error near unexpected token `|`"). Fix: pass
`-nostdin` (and/or redirect each ffmpeg call with `</dev/null`).

## Saved-clip size math (uncompressed WAV baseline, for capacity planning)
WAV bytes = duration_s × sample_rate × channels × 2 (s16le) + 44 header.
- 30 s, 48 kHz, mono = 2.88 MB (WAV) → ~1.25 MB (FLAC)
- 30 s, 16 kHz, mono = 0.96 MB (WAV) → smaller still as FLAC
Note: the Reolink sub-stream audio is only 16 kHz (8 kHz Nyquist), so 48 kHz
capture is up-sampled and carries no extra real information — but FLAC makes the
size penalty of capturing at 48 kHz negligible while staying lossless.
