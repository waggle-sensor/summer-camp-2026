# Camera Input & RTSP Patterns

## pywaggle Camera resolution chain

`Camera(device)` calls `resolve_device(device)` which routes by type:

1. **Named stream** (no `://` scheme, e.g. `bottom_camera`, `top_camera`):
   - Calls `resolve_device_from_data_config(device)` — looks up the node's
     data shim config (WES-managed) to find the actual device path or RTSP URL.
   - Only works on real Sage nodes with WES running.

2. **URL with scheme** (e.g. `rtsp://...`, `http://...`):
   - Returned as-is to `cv2.VideoCapture()`.
   - OpenCV handles RTSP natively via FFmpeg/GStreamer backends.

3. **`file://path`** (e.g. `file:///tmp/image.jpg`):
   - Strips scheme, resolves as local file path via `resolve_device_from_path()`.

4. **Path object or non-string** (e.g. `Path("/tmp/image.jpg")`):
   - Resolved via `resolve_device_from_path()`.

Under the hood, `_Capture` wraps `cv2.VideoCapture(device)` with a threading
daemon for RTSP frame draining. `snapshot()` grabs a single frame; `stream()`
yields frames continuously.

## RTSP URL formats by camera vendor

### Reolink
Reolink cameras expose RTSP on port 554 (default). Two streams per channel:

| Stream | URL | Resolution | Use case |
|--------|-----|------------|----------|
| Main | `rtsp://admin:PASSWORD@IP:554/h264Preview_01_main` | Full (4K/2K) | Recording, high-quality inference |
| Sub | `rtsp://admin:PASSWORD@IP:554/h264Preview_01_sub` | Low (640x360/480) | Preview, fast inference |

Tested models:
- **RLC-811A** (8MP PoE, 4K main / 640x360 sub) — use sub stream for YOLO
  (resizes to 640px anyway, saves bandwidth vs pulling 4K every 30s)
- **RLC-811A "HummingCam01"** on Thor node H00F — behind a router port-mapping
  10000→80 (HTTP only, no RTSP). Tested with `--snapshot-url` via CGI API.
  Camera credentials: user/password in URL query string. IR night vision
  produces grayscale images — YOLO still detects objects (bottle, vase for
  a hummingbird feeder). Future: port-map 10001→554 for RTSP streaming.

Notes:
- Channel number `01` = first camera (change for multi-channel NVRs)
- Default credentials: admin / (set during setup)
- Some newer models use `h265Preview` for H.265 streams
- WiFi models: same URLs, just use the WiFi-assigned IP
- PoE models: connect to PoE switch, camera gets DHCP address

### Axis
```
rtsp://user:pass@IP/axis-media/media.amp
rtsp://user:pass@IP/axis-media/media.amp?resolution=640x480
```

### Hikvision
```
rtsp://user:pass@IP:554/Streaming/Channels/101  (main)
rtsp://user:pass@IP:554/Streaming/Channels/102  (sub)
```

### Hanwha Wisenet (XNP-6400RW, XNP-9250R, etc.)
```
rtsp://<IP>/profile1/media.smp                    # Main stream (profile 1)
rtsp://<IP>/profile2/media.smp                    # Sub stream (profile 2)
rtsp://user:pass@<IP>:554/profile1/media.smp      # With auth
```
- Default RTSP port: 554
- PTZ PLUS series: XNP-6400RW, XNP-6400R, XNP-6400, XNP-8250R, XNP-9250R
- **Audio**: NOT available via RTSP by default on PTZ models. Requires
  SPM-4210 Network I/O Box + external microphone. When configured, audio
  is multiplexed into the RTSP stream (G.711/AAC). See
  `references/hanwha-xnp6400rw-audio.md`.
- Extract audio from RTSP (when SPM-4210 is attached):
  `ffmpeg -i "rtsp://user:pass@IP/profile1/media.smp" -vn -acodec pcm_s16le -ar 48000 -ac 1 -t 15 recording.wav`
- CGI API: `http://<IP>/stw-cgi/media.cgi?msubmenu=videoprofilepolicy&action=view`
- ONVIF Profile S/G/T supported

### ONVIF-compliant (generic)
Many IP cameras support ONVIF — use `onvif-cli` or check camera's web UI
for the RTSP URL under "Network > Stream" settings.

## ECR Plugins Using Non-Standard Cameras (Real Examples)

Two existing ECR plugins demonstrate RTSP / IP camera usage without named cameras:

### mobotix-sampler (bhupendraraut/mobotix-sampler)
- Takes `--ip`, `--user`, `--password` as separate CLI args
- Builds the camera URL internally from those components
- Uses Mobotix's EventStreamClient SDK, not pywaggle Camera
- https://github.com/waggle-sensor/plugin-mobotix-sampler

### pedestrian-direction-tracker (fmora22/pedestrian-direction-tracker)
- Takes RTSP URL via `STREAM` env var: `-e STREAM="rtsp://192.168.1.10:554/stream"`
- Falls back to pywaggle Camera via `CAMERA_FALLBACK=1` + `CAMERA=left`
- Uses YOLOv8 + ByteTrack for pedestrian flow analysis
- Thor-optimized (nvcr.io/nvidia/pytorch:25.08-py3 base)
- https://github.com/fmora22/pedestrian-direction-tracker

Both bypass the WES named camera system entirely. Our YOLO plugin takes a
simpler approach — the `--stream` flag accepts RTSP URLs directly alongside
named cameras, so no separate `--ip`/`--password` flags are needed.

## Using RTSP with Sage plugins

### Direct on DGX/workstation (local testing)
```bash
export PYWAGGLE_LOG_DIR=./output/rtsp-test
python3 app.py --stream "rtsp://admin:PASSWORD@192.168.1.100:554/h264Preview_01_main" \
    --continuous Y --interval 30
```

### On a Sage node via pluginctl
```bash
sudo pluginctl deploy -n yolo-counter \
    registry.sagecontinuum.org/flint-pete/yolo-object-counter:0.2.0 \
    -- --stream "rtsp://admin:PASSWORD@192.168.1.100:554/h264Preview_01_main" \
       --interval 30
```

Note: the RTSP camera must be network-accessible from the node/container.
On Sage nodes, cameras connected to the node's local network are reachable.

### Sage node named cameras vs RTSP
On real Sage nodes, cameras are registered in the WES data config and
accessible by name (`bottom_camera`, `top_camera`). These names resolve
to the actual RTSP URL or device path internally. For cameras NOT registered
in WES (e.g. a personal Reolink on the same network), use the RTSP URL
directly via `--stream`.

## WES data-config.json (Named Camera Registry)

On real Sage nodes, named cameras (`bottom_camera`, `top_camera`) are aliases
defined in `/run/waggle/data-config.json`. This file is managed by WES (Waggle
Edge Stack) and read by pywaggle's `resolve_device_from_data_config()`.

Format — a JSON array of device entries:

```json
[
    {
        "name": "Bottom Camera Image",
        "match": {
            "id": "bottom_camera",
            "type": "camera/image",
            "orientation": "bottom",
            "resolution": "800x600"
        },
        "handler": {
            "type": "image",
            "args": {
                "url": "rtsp://10.31.81.10:554/stream1"
            }
        }
    },
    {
        "name": "Reolink RLC-811A",
        "match": {
            "id": "reolink_camera",
            "type": "camera/video",
            "orientation": "street"
        },
        "handler": {
            "type": "video",
            "args": {
                "url": "rtsp://admin:PASSWORD@10.31.81.XX:554/h264Preview_01_main"
            }
        }
    }
]
```

Resolution chain: `Camera("bottom_camera")` → reads config → finds entry
with `match.id == "bottom_camera"` → extracts `handler.args.url` → passes
URL to `cv2.VideoCapture()`.

For custom IP cameras not registered in WES, bypass the config entirely
by passing the RTSP URL directly to `--stream`.

Source: `waggle-sensor/virtual-waggle/data-config.json` (reference example),
pywaggle `waggle.data.vision.resolve_device_from_data_config()`.

## Docker Run on Thor with RTSP Camera (QA Testing)

When Thor has Docker installed (in addition to k3s), you can run the
container manually with volume mounts for easy QA inspection — just
like testing on the DGX build machine:

```bash
# On DGX Spark (build machine): save and transfer
docker save yolo-object-counter:0.2.0 | gzip > /tmp/yolo.tar.gz
scp /tmp/yolo.tar.gz beckman@thor-node:~/

# On Thor: load and run with Docker (sudo required)
sudo docker load < ~/yolo-object-counter.tar.gz

# Or if you built directly on Thor (faster iteration):
# cd ~/sage-yolo && git pull && sudo docker build --no-cache -t yolo-object-counter:0.2.0 .

mkdir -p ~/yolo-reolink-test

sudo docker run --rm --runtime=nvidia \
    -e PYWAGGLE_LOG_DIR=/output \
    -v ~/yolo-reolink-test:/output \
    yolo-object-counter:0.2.0 \
    --stream "rtsp://admin:PASSWORD@REOLINK_IP:554/h264Preview_01_sub" \
    --interval 30 --continuous Y

# In another terminal, watch results:
tail -f ~/yolo-reolink-test/data.ndjson
ls -la ~/yolo-reolink-test/uploads/
```

Key points:
- Use the **sub stream** (`h264Preview_01_sub`, 640x360) for testing —
  YOLO resizes to 640px anyway, and it's much less bandwidth than 4K
- Volume mount `-v ~/yolo-reolink-test:/output` captures data.ndjson and
  uploads/ on the host for easy inspection and scp transfer
- If Thor only has k3s (no Docker), use `sudo k3s ctr images import`
  and `sudo pluginctl deploy` instead — but output stays inside the
  container's ephemeral filesystem

Note: `docker load` (Docker) vs `k3s ctr images import` (containerd) —
use whichever runtime is available on the node.

## Reolink HTTP Snapshot API (when RTSP is not available)

When a camera is behind a router that only port-maps HTTP (port 80) but not
RTSP (port 554), use the Reolink CGI snapshot endpoint instead of RTSP:

```
http://<IP>:<PORT>/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=<random>&user=<user>&password=<pass>
```

This returns a single JPEG image (mainstream resolution, e.g. 3840x2160 for RLC-811A).

For substream resolution, append `&width=640&height=480`:
```
http://<IP>:<PORT>/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=abc&user=CAMERA_USER&password=CAMERA_PASSWORD&width=640&height=480
```

**Important**: `cv2.VideoCapture()` (used by pywaggle's Camera class) CANNOT
open this URL — it expects a video stream, not a CGI endpoint returning a
single JPEG. For one-shot testing, curl the snapshot to a file and pass it
to `--stream file:///path/to/snapshot.jpg` or `--image-dir`.

Workflow for HTTP-only cameras:
```bash
# Grab snapshot
curl -s -o /tmp/cam-snap.jpg \
  'http://CAMERA_IP:PORT/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=test&user=CAMERA_USER&password=CAMERA_PASSWORD'

# Run YOLO on the snapshot
sudo docker run --rm --runtime=nvidia \
  -e PYWAGGLE_LOG_DIR=/output \
  -v ~/yolo-test:/output \
  -v /tmp/cam-snap.jpg:/images/snap.jpg:ro \
  yolo-object-counter:0.2.0 \
  --stream file:///images/snap.jpg --continuous N
```

For continuous monitoring with HTTP-only cameras, either:
1. Ask the network admin to port-map RTSP (port 554) through the router
2. Use the plugin's `--snapshot-url` flag (added in sage-yolo 0.2.0) which
   fetches a JPEG via `urllib.request` + `cv2.imdecode()` each cycle:

```bash
sudo docker run --rm --runtime=nvidia \
    -e PYWAGGLE_LOG_DIR=/output \
    -v ~/yolo-reolink-test:/output \
    yolo-object-counter:0.2.0 \
    --stream "rtsp://admin:PASSWORD@REOLINK_IP:554/h264Preview_01_sub" \
    --interval 30 --continuous Y
```

With `--continuous Y --interval 30`, it fetches a new snapshot every 30s.
With `--continuous N`, it grabs one frame, runs YOLO, publishes, and exits.

The `--snapshot-url` implementation uses `fetch_snapshot()` in app.py:
`urllib.request.urlopen()` → `np.frombuffer()` → `cv2.imdecode()` → BGR numpy.
No pywaggle Camera dependency. Works with any HTTP URL returning a JPEG image.

## Troubleshooting RTSP

- **No RTSP port-mapping through router**: If only HTTP (port 80) is port-mapped, RTSP won't work. Use the plugin's `--snapshot-url` flag with the Reolink HTTP CGI snapshot API instead. See `references/reolink-http-snapshot.md`.
- **Connection refused**: Check port 554, camera powered on, firewall rules
- **Authentication failed**: Verify username/password (URL-encode special chars)
- **Frame grab timeout**: Camera may be in use by another stream consumer;
  some cameras limit concurrent RTSP sessions (typically 2-4)
- **Latency/buffering**: OpenCV buffers RTSP frames; pywaggle's `_Capture`
  daemon thread drains the buffer to keep the latest frame fresh
- **H.265 not supported**: OpenCV's FFmpeg backend may not decode H.265;
  use H.264 stream URL instead (`h264Preview` not `h265Preview`)
- **Test connectivity**: `ffprobe rtsp://admin:pass@IP:554/h264Preview_01_main`
  should show stream info if the camera is reachable
