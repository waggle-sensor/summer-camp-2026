# RTSP metadata preservation: why the video stream is the wrong source

Key analysis (2026-07) for any image-capture plugin trying to preserve
camera-authored metadata. Companion to camera-metadata-and-native-still-
acquisition.md (which has the marker-scan evidence) and camera-rtsp-patterns.md.

## The trap and the correction
A natural but WRONG assumption: "pull raw bytes over RTSP instead of letting
OpenCV re-encode, and camera metadata is preserved." It is NOT — for the streams
these cameras actually serve.

- pywaggle `Camera(device)` routes EVERYTHING through OpenCV -> FFmpeg/libav:
  decode to pixels, re-encode on save. This is the easy, uniform, lossy path. The
  `Lavc...` COM tag in a stored JPEG is the tell it went through libav (metadata
  already gone).
- The RTSP main/sub stream is **H.264 / H.265** — inter-frame compressed video
  (I/P/B NAL units). There is **NO per-frame JPEG/EXIF envelope** in that stream.
  The camera's still-image metadata (EXIF, Mobotix M1IMG, etc.) was NEVER
  transmitted. So a raw keyframe grab yields a metadata-free (not even JPEG) frame;
  OpenCV re-encode "loses" nothing metadata-wise there — only pixel generation.
- Metadata lives in a SEPARATE endpoint, not the video stream:
  - HTTP/vendor snapshot still (raw JPEG with segments intact):
    Reolink `cgi-bin/api.cgi?cmd=Snap`; Hanwha SUNAPI
    `/stw-cgi/video.cgi?msubmenu=snapshot&action=view&Profile=P&Channel=N`;
    Mobotix `/record/current.jpg` | `/cgi-bin/image.jpg` | `/control/event.jpg`.
  - MJPEG RTSP profile (when configured): every frame IS a full JPEG, so a raw
    frame grab preserves metadata; here OpenCV re-encode WOULD destroy it.
  - Hanwha SUNAPI snapshot returns a JPEG "based on the MJPEG profile" and ERRORS
    if no MJPEG profile is configured on that Profile.

## Acquisition ladder (best -> floor) — what a plugin/pywaggle2 should try
1. Native HTTP/vendor snapshot still — raw JPEG bytes, metadata preserved. BEST.
2. MJPEG RTSP profile frame — raw JPEG, no decode. Metadata preserved if authored.
3. H.264/H.265 RTSP decode -> JPEG (OpenCV) — floor. No metadata in stream to
   lose; only pixel re-compression. Universal fallback.
Bias to the highest rung the camera supports; slide down only when forced.

## Design consequence
Vendor "try native still, else OpenCV" logic is CAMERA-domain knowledge, not
plugin-domain. It belongs in pywaggle's Camera so all plugins inherit it. The
metadata-inject rule: INSERT an EXIF/COM segment into the existing JPEG byte
stream (piexif-style), NEVER pixel-decode to add metadata.

## WSN camera facts (fleet)
Hanwha XNV-8081Z / XNF-8010RV: triple-codec H.265/H.264/MJPEG, ONVIF, top/bottom
pairs, all IP/RTSP. The metadata-preserving path for them is the SUNAPI HTTP still
(needs an MJPEG profile enabled), NOT the RTSP H.264 stream. Open verification
items: do the WSN units have an MJPEG profile configured, and what EXIF does a
real Hanwha snapshot actually carry (unverified on a Sage unit).

## Full redesign proposal
~/AI-projects/pywaggle2-design.md §1 (acquisition ladder) captures this in full.
