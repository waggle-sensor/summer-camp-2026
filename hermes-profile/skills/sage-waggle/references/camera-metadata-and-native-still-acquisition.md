# Camera JPEG metadata: vendor interfaces, re-encode loss, native-still acquisition

Verified with live evidence (2026-07-03): direct camera pulls + object-store
frames marker-scanned byte-by-byte. Use this when building/updating any Sage
image-capture plugin (imagesampler and derivatives) and deciding HOW to acquire a
frame so high-quality-camera metadata survives.

Companions under this umbrella:
- `pywaggle-upload-naming-and-timestamps.md` (how uploads are named/timestamped)
- `linking-images-to-event-log-and-uniqueness.md` (consumer/forensic side)

## The core lesson (one sentence)

Whether camera-authored JPEG metadata (manufacturer, capture time, per-sensor
exposure/geometry) reaches the object store is decided by TWO things: (a) the
camera vendor, and (b) whether the plugin RE-ENCODES the frame. Any pipeline that
decodes to pixels and re-encodes (OpenCV/libav, `cv2.imwrite`) DESTROYS it.

## Evidence — three marker-scanned frames

| Source | Acquisition path | Camera metadata in stored JPEG |
|--------|------------------|-------------------------------|
| Reolink RLC-811A (H00F) | `cmd=Snap` native HTTP still | NONE — bare JPEG (DQT/SOF/DHT/scan only; no EXIF/JFIF). This camera authors none. |
| Mobotix (W08D) via `mobotix-scan` | libav/FFmpeg decode→re-encode | STRIPPED — only a `Lavc58.54.100` comment (FFmpeg's own encoder tag) |
| Mobotix (W08D) via `imagesampler-mobotix` | raw native JPEG, NOT re-encoded | FULL Mobotix `#:M1IMG` fingerprint (2001 B) + `MXF` binary block (301 B) |

Same Mobotix camera model, two plugins, opposite outcomes — the ONLY difference
is re-encode vs raw bytes. That is the whole design argument in one comparison.
The `Lavc...` comment is the tell that a frame went through FFmpeg/libav
(OpenCV's backend) and therefore lost any camera metadata.

## What a Mobotix native JPEG actually embeds (decoded M1IMG)

```
#:M1IMG  SECTION FINGERPRINT
  PRD=MOBOTIX            manufacturer
  FRM=7290841           frame number
  DAT=2026-07-03  TIM=21:00:08.323  TZN=GMT   camera-side capture date/time (ms) + TZ
  TIT=1783112408.323  TIU=323875              epoch capture time + microseconds
SECTION IMAGE
  CTY=DUAL  ICC=MxPEG  XTO=6144 YTO=2048  QLT=60
  CAM=BOTH  WIN=lt=...:cam=1  WIN=lt=...:cam=0   per-sensor window geometry
  SNR=...  ZOM=1000,1000  ACT=OFF,AUTO  BRT/BLT/CSA/NOI   per-sensor exposure telemetry
  (+ MXF binary block: sensor calibration/exposure)
```
Richer than typical EXIF, and includes a TRUE CAMERA-SIDE capture time — better
than pywaggle's node grab-time (see timestamps ref). Preserve it and you get
authoritative capture time for free on Mobotix.

## Vendor acquisition interfaces (they differ — DO NOT generalize from one camera)

- **Reolink** (e.g. RLC-811A): proprietary JSON API `cgi-bin/api.cgi?cmd=Snap`
  (or RTSP). Query-param auth. This model embeds no metadata even on its own
  snapshot.
- **Hanwha / Wisenet**: SUNAPI still endpoint (per Hanwha docs 2026)
  `http://<IP>/stw-cgi/video.cgi?msubmenu=snapshot&action=view&Profile=<P>&Channel=<N>`
  (distinct from RTSP), full ONVIF. Returns a JPEG "based on the MJPEG profile" —
  and ERRORS if no MJPEG profile is configured on that Profile. Professional line —
  snapshots commonly carry EXIF (make/model/datetime) and OSD. (Not yet
  marker-scanned on a Sage unit — open item; also unverified whether WSN units
  have an MJPEG profile enabled.)
- **Mobotix** (e.g. M16): multiple native stills — `/record/current.jpg`,
  `/cgi-bin/image.jpg?...`, `/control/event.jpg?sequence=head`; MJPEG/MxPEG via
  `/cgi-bin/faststream.jpg`. Embeds the M1IMG fingerprint above.

## CRUCIAL: the RTSP video stream carries NO per-frame metadata (2026-07-07)

A natural but WRONG assumption is "pull raw bytes over RTSP instead of
re-encoding, and camera metadata is preserved." It is NOT, for the streams these
cameras actually serve. Metadata preservation is about choosing the right ENDPOINT,
not about avoiding re-encode on the video stream:

- The RTSP main/sub stream is **H.264 or H.265** — inter-frame compressed video
  (I/P/B NAL units). There is **no per-frame JPEG/EXIF envelope** in it. The
  camera's still metadata was never transmitted over that stream. A raw keyframe
  grab yields a metadata-free (and not even JPEG) frame; OpenCV re-encode "loses"
  nothing metadata-wise there (only a generation of pixel quality) because there
  was nothing to lose.
- The metadata-rich, loss-free source is a SEPARATE endpoint:
  1. **HTTP/vendor snapshot still** → real JPEG w/ camera segments intact
     (Reolink `cmd=Snap`, Hanwha SUNAPI snapshot, Mobotix `image.jpg`). BEST.
  2. **MJPEG RTSP profile** (when configured) → every RTSP frame IS a full JPEG;
     raw grab preserves metadata, OpenCV re-encode would destroy it.
  3. **H.264/H.265 RTSP decode→JPEG** (OpenCV) → lowest common denominator FLOOR;
     no metadata in the stream to preserve.
- Hanwha SUNAPI snapshot returns a JPEG "based on the MJPEG profile" and ERRORS
  if no MJPEG profile is configured — so a still endpoint can require an MJPEG
  profile to exist on the camera.

Acquisition ladder to try (best→floor), tagging result with how it was obtained:
native-http-still → mjpeg-rtsp-raw → opencv-reencoded. This vendor-aware ladder is
camera-DOMAIN knowledge (belongs in pywaggle's Camera, ideally), not per-plugin.
WSN cameras of record: Hanwha XNV-8081Z, XNF-8010RV (triple-codec H.265/H.264/
MJPEG, ONVIF, top/bottom pairs — all IP/RTSP). Full redesign writeup lives in
`~/AI-projects/pywaggle2-design.md` §1.

## Design mandate for image-capture plugins (adopted)

1. **PRIMARY: raw native still.** Fetch the camera's native still endpoint and
   save the RAW JPEG BYTES UNTOUCHED — no decode, no re-encode. Preserves
   whatever the camera authored.
2. **INJECT, don't rebuild.** Add Sage fields (vsn, node, job/task,
   plugin+version, capture/grab ts, upload ts, per-capture uid, lat/lon) by
   INSERTING an EXIF/COM segment into the existing byte stream, leaving the
   camera's own segments intact. Never pixel-decode to add metadata.
3. **FALLBACK: OpenCV/RTSP** only when no native still exists (stream-only source).
   Accept pixels-only + re-encode; still add our fields; label as re-encoded.
4. **Preserve-if-present is NOT a no-op:** Mobotix → full fingerprint; Hanwha →
   likely EXIF; Reolink → nothing (harmless). One defensive path serves the fleet.
5. **Capture time:** prefer camera-side (Mobotix TIM/TZN/TIT) when present, else
   node grab-time; always also record `upload_timestamp`.

Architecture consequence: native-still HTTP fetch (raw bytes) is a FIRST-CLASS
acquisition source; pywaggle `Camera()`/OpenCV is the fallback for stream-only
cameras. The generic imagesampler's OpenCV path is vendor-neutral but lossy — it
was chosen for uniformity, and metadata loss is an unintended side effect.

## Reusable probe: marker-scan a JPEG for metadata (no exiftool needed)

Nodes often lack exiftool/identify. Scan JPEG segments with stdlib. Presence of
APP1(EXIF)/APP0(JFIF)/COM segments before SOS (0xFFDA) = metadata; a lone
`Lavc...` COM = re-encoded by FFmpeg (metadata already lost).

```python
import struct
raw = open("frame.jpg","rb").read()
i = 2
M = {0xE1:"APP1/EXIF",0xE0:"APP0/JFIF",0xED:"APP13/IPTC",0xFE:"COM",0xDA:"SOS"}
while i < len(raw)-1:
    if raw[i] != 0xFF: i += 1; continue
    m = raw[i+1]
    if m == 0xDA: print("SOS — pixels begin"); break
    if m in (0xD8,0xD9) or 0xD0 <= m <= 0xD7: i += 2; continue
    seglen = struct.unpack(">H", raw[i+2:i+4])[0]
    payload = raw[i+4:i+4+seglen-2]
    print(f"0x{m:02X} {M.get(m,'0x%02X'%m):10} len={seglen}  {payload[:24]!r}")
    i += 2 + seglen
```

## Auth/access notes (from this session)

- Downloading a protected object-store object needs auth: `Authorization: Sage
  <portal-token>` header works (Bearer also tried; Sage scheme succeeded). A
  signed URL with `?authz=<SciToken JWT>` is directly fetchable, no header.
- The object store host for node-data can be
  `https://storage.sagecontinuum.org/...` OR
  `https://nrdstor.nationalresearchplatform.org:8443/sage/node-data/...` — both
  seen for Sage uploads.
- Sending camera creds through `ssh 'curl ...!...'` risks bash history-expansion
  mangling the `!`; a script FILE on the node or a Python `urllib` request avoids
  shell quoting entirely (cleanest for probing).

## Open items
- Marker-scan a real Hanwha native snapshot on the fleet to confirm it carries EXIF.
- Confirm exact native still URLs + auth per camera the plugin will target.
- Confirm WSN Hanwha units (XNV-8081Z/XNF-8010RV) have an MJPEG profile enabled
  (required for the SUNAPI snapshot to return a JPEG rather than error).

## Broader redesign
The acquisition ladder + node-identity gap are consolidated into a next-gen client
library proposal at `~/AI-projects/pywaggle2-design.md` (camera ladder §1,
get_node_info() §2, lib enhancements from Infra-problems-to-fix §3). The vendor
"try native still, else OpenCV" logic ideally lives in pywaggle's Camera, not
per-plugin. Tracked issues + their filed status live in
`~/AI-projects/Infra-problems-to-fix.md`.
