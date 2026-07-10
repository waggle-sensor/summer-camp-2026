# Slack Notification for Sage Plugin Detections

## Architecture: Cloud Trigger Pattern

Sage's recommended pattern for reacting to edge detections. A watcher script runs
externally (laptop, server, DGX Spark — NOT on the Sage node) and polls the public
data API. When it sees a detection, it posts to Slack.

```
  Sage Node (Thor)              Sage Cloud                Watcher Script
  ┌──────────────┐        ┌──────────────────┐       ┌──────────────────┐
  │ YOLO/BioCLIP │        │  Data API        │       │                  │
  │ detects bird │─publish─▶ stores records  │◀─poll──│ hummingbird-     │
  │ publishes    │        │ (public, no auth) │       │ watcher.py       │──▶ Slack
  │ env.count.*  │        └──────────────────┘       └──────────────────┘
  └──────────────┘
```

Key constraints:
- Sage containers are network-restricted — can't reach external services
- Regular SSH processes on Thor CAN reach external URLs (tested with hooks.slack.com)
- The data API is public and unauthenticated — polling is free

Official Sage examples of this pattern:
- `waggle-sensor/wildfire-trigger-example` — polls `env.smoke.tile_probs`, adjusts job scheduling
- `waggle-sensor/severe-weather-trigger-example` — polls NWS API, suspends/resumes edge jobs

## Slack Setup

Two Slack mechanisms, each serving a different purpose:

### 1. Incoming Webhook (text alerts)
- Create at https://api.slack.com/messaging/webhooks
- Single URL: `https://hooks.slack.com/services/T.../B.../...`
- Supports text, blocks, and `image_url` (must be publicly accessible)
- Does NOT support file uploads

### 2. Bot Token + slack_sdk (image uploads)
- Create a Slack app at https://api.slack.com/apps
- OAuth scopes: `files:write`, `chat:write`
- Install to workspace, invite bot to channel
- Uses `client.files_upload_v2()` (the old `files.upload` was retired March 2025)
- `pip install slack_sdk`

### Secrets management
Store in `secrets/` directory (gitignored):
- `secrets/webhook-url.txt` — one line, the webhook URL
- `secrets/bot-secrets` — shell export format: `export SLACK_BOT_TOKEN="xoxb-..."` etc.
- `<YOUR_SAGE_TOKEN_FILE>` — Sage portal access token for image downloads
- `chmod 600` all secrets files

## Querying for Detections (Data API)

```python
import json, urllib.request

body = {
    "start": "-2m",
    "tail": 100,
    "filter": {"vsn": "H00F", "name": "env.count.bird"},
}
req = urllib.request.Request(
    "https://data.sagecontinuum.org/api/v1/query",
    data=json.dumps(body).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
with urllib.request.urlopen(req, timeout=30) as resp:
    lines = resp.read().decode().strip().split("\n")
    records = [json.loads(line) for line in lines if line.strip()]
```

Multiple measurements: query each separately (the API filter accepts one `name` at a time,
not a list). Use wildcard `env.count.*` to get all counts in one query.

## Downloading Annotated Images from Sage Storage

```bash
# MUST use -L to follow 302 redirect to NRP storage
curl -L -u username:portal-access-token -o image.jpg "<storage-url>"
```

The storage API returns a 302 redirect to `nrdstor.nationalresearchplatform.org:8443`
with a signed JWT. Without `-L`, you get an empty/0-byte file.

**Known issue**: NRP storage can lag or break globally. The upload agent on the node
works fine (rsync to beehive-uploads), but Beehive-to-NRP sync can fail. All recent
uploads 404 while old files still work. Escalate to Sage infrastructure team.

## BioCLIP Species Enrichment

When YOLO detects a "bird", query BioCLIP's species prediction from the same timeframe:

```python
# After detecting env.count.bird > 0, also query:
species_records = query("env.species.species", vsn="H00F", start="-5m")
confidence_records = query("env.species.species.confidence", vsn="H00F", start="-5m")
```

Combine in the Slack message:
```
🐦 Detection at the hummingbird feeder! (bird — 1 total)
  • 1 bird(s) at 2026-06-18T10:52:34Z [camera: http-snapshot, model: yolo11x.pt]
🧬 BioCLIP species ID: *Archilochus colubris* (97% confidence)
```

## Watcher Script Design

Key features of `hummingbird-watcher.py`:
- **Startup**: prints to stdout AND posts to Slack
- **Shutdown** (Ctrl+C): posts goodbye to Slack
- **Cooldown**: configurable (default 5min) between alerts to avoid spam
- **Multi-measurement**: watches env.count.bird + env.count.person + env.count.fork
- **No pip deps**: pure stdlib (urllib, json, time) for the core watcher
- **slack_sdk only for image uploads**: separate script `slack_post_image.py`
- **Secrets auto-loading**: checks CLI → env var → secrets/ directory
- **`--dry-run`** mode for testing without hitting Slack

## Image Annotation for BioCLIP

BioCLIP annotates output images with orange text overlay:
- Above min-confidence threshold: top-5 species predictions in top-left corner
- Below threshold: "No confident species prediction (best: X%)" at bottom
- Font scales to image size: `scale = max(0.5, min(w, h) / 1000.0)`
- Orange in BGR: `(0, 165, 255)` with black background rectangles for readability
- Production mode: only upload annotated images above threshold
- Test mode (--image-dir): upload all images for review

## Reference Files

- Working implementation: `~/AI-projects/slack-hummingbird/`
- YOLO plugin: `~/AI-projects/sage-yolo/`
- BioCLIP plugin: `~/AI-projects/sage-bioclip/`
