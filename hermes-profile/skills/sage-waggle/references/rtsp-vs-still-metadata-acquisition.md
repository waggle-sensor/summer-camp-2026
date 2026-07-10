# RTSP video vs HTTP still: where camera metadata actually lives

Verified via vendor docs + fleet marker-scans (2026-07). Read this BEFORE building
multi-vendor camera support in any image-capture plugin (imagesampler and
derivatives). It resolves the common but WRONG framing "pull RTSP frames while
preserving camera metadata."

## The core finding (one sentence)

An H.264/H.265 RTSP video stream carries NO per-frame JPEG metadata to preserve —
that metadata only exists in a JPEG still (HTTP snapshot or an MJPEG profile), so
the metadata-preserving acquisition path is the vendor's HTTP still endpoint, NOT
the RTSP video stream.

## Why "preserve metadata from the RTSP pull" is a category error for H.264/H.265

- A JPEG still is a self-contained image with APP1/EXIF, COM, and vendor segments
  (Mobotix `#:M1IMG` fingerprint, Hanwha EXIF, etc.) wrapped around the pixels.
- An H.264/H.265 RTSP stream is a sequence of NAL units (I/P/B motion-compensated
  video packets). There is NO per-frame EXIF/JPEG-metadata envelope. Camera still
  metadata is simply not in the video elementary stream. Any timing/parameter data
  lives in the RTSP/RTP session layer (SDP, RTCP sender reports, H.264 SEI) — not
  as JPEG segments.
- Therefore OpenCV re-encoding an H.264/H.265 keyframe is NOT destroying metadata —
  there was none in the encoded video to lose. The only "loss" is generational
  pixel re-compression. `ffmpeg -c:v copy` of a keyframe gives a raw H.264 frame
  (not even a JPEG) that is still metadata-free.

## Three acquisition cases (they are genuinely different)

| Source | Per-frame JPEG metadata? | Right approach |
|--------|--------------------------|----------------|
| H.264/H.265 RTSP main/sub stream (the default) | NONE (not in stream) | decode→JPEG is fine (nothing to lose); OpenCV/pywaggle Camera path acceptable |
| MJPEG-over-RTSP profile (if configured) | YES (each frame is a full JPEG) | raw JPEG frame grab, NO decode/re-encode; OpenCV here WOULD strip it |
| HTTP still endpoint (Reolink cmd=Snap / Hanwha SUNAPI) | YES (EXIF/vendor segments) | native-still: fetch raw bytes via urllib → inject Sage EXIF → never decode |

## Vendor HTTP still endpoints (the metadata-preserving path)

- **Reolink** (e.g. RLC-811A): `cgi-bin/api.cgi?cmd=Snap&channel=0&user=&password=`
  (query-param auth, no %-encode). This model authors NO metadata even on its own
  snapshot (harmless — bare JPEG in, bare JPEG out).
- **Hanwha/Wisenet** (e.g. XNV-8081Z, XNF-8010RV — triple-codec H.265/H.264/MJPEG,
  ONVIF): SUNAPI snapshot
  `http://<IP>/stw-cgi/video.cgi?msubmenu=snapshot&action=view&Profile=1&Channel=N`.
  Hanwha docs: returns "a JPEG snapshot BASED ON THE MJPEG PROFILE"; returns an
  ERROR if no MJPEG profile is configured. Exact analog of Reolink cmd=Snap. Fits
  image-sampler2's native-still design identically — add `build_hanwha_snapshot_url()`
  beside `build_reolink_snap_url()`, same acquisition path, different URL template.
- **Mobotix** (e.g. M16): `/record/current.jpg`, `/cgi-bin/image.jpg?...`,
  `/control/event.jpg?sequence=head`. Embeds the richest metadata on the fleet
  (M1IMG: manufacturer, frame#, TRUE camera-side capture time ms+µs, per-sensor
  exposure/geometry, MXF calibration). For Mobotix, OpenCV re-encode is the WORST
  outcome — it discards a camera-side capture time better than pywaggle's node
  grab-time. See `camera-metadata-and-native-still-acquisition.md`.

## Design consequence for image-sampler2

Two coherent philosophies point different directions — you can't get both from one
H.264 RTSP pull:
- **Metadata preservation** → RTSP video is the WRONG source for these cameras;
  the HTTP still (SUNAPI / cmd=Snap) is right and drops into the existing
  native-still model (raw bytes + EXIF inject, no decode). Highest-value,
  lowest-risk multi-vendor move: add a Hanwha SUNAPI snapshot builder mirroring
  Reolink.
- **Universal RTSP reach** (any camera, named-shortcut convenience) → use pywaggle
  Camera/OpenCV, accept H.264/H.265 has no metadata anyway, only worry about
  re-encode loss in the MJPEG-over-RTSP sub-case.

## Verify on real hardware before building a Hanwha path (open items)

1. Do the WSN Hanwha cameras have an MJPEG profile configured, so the SUNAPI
   snapshot returns a JPEG (vs erroring)? If not, someone must enable one in the
   camera config.
2. What metadata does a real XNV-8081Z / XNF-8010RV snapshot actually carry?
   Hanwha EXIF is "likely" but UNVERIFIED on a Sage unit. Marker-scan a real
   snapshot (see the stdlib segment scanner in
   `camera-metadata-and-native-still-acquisition.md`) to confirm it's worth
   preserving for this vendor the way it clearly is for Mobotix.

## Original plugin-imagesampler for reference

Upstream `waggle-sensor/plugin-imagesampler` (v0.3.8) had NO vendor logic — it
delegated everything to `pywaggle Camera().snapshot()` → OpenCV/libav → re-encode.
One uniform path for all vendors: vendor-agnostic but lossy. The `Lavc...` COM tag
in a stored JPEG is the tell that a frame went through FFmpeg/libav and lost any
camera metadata. image-sampler2 inverts this: native-still raw bytes first,
OpenCV/RTSP only as a stream-only fallback.
