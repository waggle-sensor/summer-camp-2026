# Hanwha XNP-6400RW — Audio Capture for BirdNET

## Key Finding: No Built-in Microphone

The XNP-6400RW is a 2MP 40x IR PTZ camera with wiper.
It does **NOT** have a built-in microphone.

From the datasheet (Aug 2020):
> Audio detection, Sound classification (**with NW I/O Box**)

Audio features require the **SPM-4210 Network I/O Box** — a separate
accessory providing mic input, audio output, and alarm I/O.

## RTSP Stream (Video Only Without SPM-4210)

Hanwha Wisenet PTZ camera RTSP URLs:
```
rtsp://<IP>/profile1/media.smp             # Main stream (profile 1)
rtsp://<IP>/profile2/media.smp             # Sub stream (profile 2)
rtsp://user:pass@<IP>:554/profile1/media.smp  # With auth
```
Default RTSP port: 554. Without the SPM-4210, these streams carry
video only (H.265/H.264/MJPEG, no audio track).

## Option 1: SPM-4210 I/O Box + External Microphone

The SPM-4210 connects to the camera via the network and provides:
- Mic input jack (3.5mm or terminal block)
- Audio output
- Alarm I/O (4 inputs, 2 outputs)

When configured, the camera multiplexes audio into the RTSP stream
as a secondary track (G.711 μ-law or AAC). Extract with ffmpeg:
```bash
ffmpeg -i "rtsp://user:pass@CAMERA_IP/profile1/media.smp" \
       -vn -acodec pcm_s16le -ar 48000 -ac 1 \
       -t 15 recording.wav
```

Camera web UI: Setup → Audio → enable audio input, select codec.
The `-ar 48000` flag resamples to BirdNET's required 48 kHz.

### Outdoor Microphone Considerations
- Needs weatherproof housing (IP67+) for outdoor deployment
- Wind noise is the #1 issue — use a foam windscreen or dead cat
- Directional microphones reduce ambient noise but narrow pickup
- Omnidirectional is better for general wildlife monitoring
- Consider frequency response: birdsong ranges 1-10 kHz,
  most security mics are optimized for voice (300 Hz-3.4 kHz)

## Option 2: USB Microphone on the Sage Node (Thor)

Bypass the camera entirely. Plug a USB mic into the Thor node.
The pywaggle `Microphone` class uses `soundcard.default_microphone()`
(ALSA/PulseAudio). The existing BirdNET app.py supports this:
```bash
python3 app.py --duration 15 --min-confidence 0.25
# Records from default USB mic, classifies, publishes
```
No code changes needed. The mic just needs to be physically near
the forest — it doesn't have to be on the camera.

### pywaggle Microphone internals
```python
class Microphone:
    def __init__(self, samplerate=48000, channels=1, name=None):
        import soundcard
        self.microphone = soundcard.default_microphone()
        # ...
    def record(self, duration):
        data = self.microphone.record(
            samplerate=self.samplerate,
            numframes=int(duration * self.samplerate),
            channels=self.channels,
        )
        return AudioSample(data, self.samplerate, timestamp=timestamp)
```
No RTSP support — it only records from the system's default audio
input device. For RTSP audio extraction, use ffmpeg as shown above.

## Option 3: Standalone Audio Capture Device

Deploy a Raspberry Pi + USB mic near the camera location.
Stream audio to Thor over the network. More complex but allows
optimal microphone placement independent of camera position.

## Recommendation

For initial BirdNET deployment: **Option 2 (USB mic on Thor)** is
simplest. The plugin already supports it. For tighter camera
integration: **Option 1 (SPM-4210)** with an outdoor-rated mic.

## Camera Specs (relevant subset)

- Resolution: 1920x1080 (2MP)
- Zoom: 4.25-170mm (40x optical)
- IR range: 200m
- Codec: H.265/H.264/MJPEG, WiseStream II
- Network: 10/100BASE-T, PoE+ (HPoE, IEEE802.3bt)
- Weather: IP66, IK10, NEMA4X, -40°C to +55°C
- Analytics: object tracking, face detection, virtual line, etc.
  (audio analytics require SPM-4210)
- Wisenet 7 series — supports ONVIF Profile S/G/T, SUNAPI
- Datasheet: https://hanwhavisionamerica.com/wp-content/uploads/attachments/d/a/datasheet_xnp-6400rw_201020_en.pdf
