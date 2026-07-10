# Cloud Trigger / External Notification Pattern

## Concept

Sage containers on edge nodes are network-restricted — they cannot reach external services (Slack, email, webhooks). Host processes on some nodes (e.g. Thor via SSH) CAN reach the internet, but the recommended pattern is a **cloud trigger**: a script running externally (laptop, server, cloud VM) that polls the public Sage data API and reacts when it sees specific measurements.

## Architecture

```
  Sage Node (container)         Sage Cloud              External watcher
  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
  │ Plugin publishes  │    │ Data API         │    │ Polls data API   │
  │ env.count.bird   │──▶ │ (public, no auth)│◀── │ every N seconds  │──▶ Slack/email/etc
  └──────────────────┘    └──────────────────┘    └──────────────────┘
```

## Querying for detections (stdlib only, no pip deps)

```python
import json, urllib.request

def query_sage_data(vsn, measurements, start="-2m", tail=100):
    """Query one or more measurements. Returns list of records."""
    if isinstance(measurements, str):
        measurements = [measurements]
    all_records = []
    for measurement in measurements:
        body = {"start": start, "tail": tail,
                "filter": {"vsn": vsn, "name": measurement}}
        req = urllib.request.Request(
            "https://data.sagecontinuum.org/api/v1/query",
            data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=30) as resp:
            lines = resp.read().decode().strip().split("\n")
            all_records.extend([json.loads(l) for l in lines if l.strip()])
    return all_records
```

Note: the Sage data API doesn't support OR queries on `name` — issue one call per measurement.

## Querying for uploaded images

Plugin images uploaded via `plugin.upload_file()` appear as `name: "upload"` records. Filter by plugin to get specific images:

```python
body = {"start": "-10m", "tail": 5,
        "filter": {"vsn": "H00F", "name": "upload",
                   "plugin": "docker.io/library/yolo-object-counter:0.2.0"}}
```

The `value` field is the Sage storage URL. The `meta.filename` field has the original name (e.g. `http-snapshot-annotated.jpg`). The `meta.detections` field has the count.

## Downloading images from Sage storage

**Always use `curl -L`** (follow redirects). Storage returns 302 → NRP backend:

```bash
curl -L -u <portal-username>:<access-token> -o image.jpg "<sage-storage-url>"
```

In Python, use subprocess + curl (urllib fails on NRP's double-redirect chain):

```python
import subprocess
result = subprocess.run(
    ["curl", "-s", "-f", "-L", "-u", f"{user}:{token}",
     "-o", output_path, "--max-time", "30", image_url],
    capture_output=True, text=True, timeout=45)
success = result.returncode == 0
```

**NRP propagation delay/outages**: Recently uploaded images may 404. Can be propagation (minutes) or a global sync outage (hours+, affects all nodes). Diagnostic: if old images work but ALL recent ones from ALL nodes fail, it's a global outage. Check node-side upload agent: `sudo kubectl logs wes-upload-agent-<id> --tail=30` — if it shows normal scan/upload/cleanup cycles, the problem is downstream (Beehive → NRP).

**Alternative when NRP is down**: SSH to the node and grab a fresh camera snapshot directly from the IP camera, bypassing NRP entirely:
```bash
ssh beckman@node-H00F.sage "curl -s 'http://IP:PORT/cgi-bin/api.cgi?cmd=Snap&channel=0&...'" > /tmp/snapshot.jpg
```

## Slack integration

### Text alerts via incoming webhook (no pip deps)

```python
def post_to_slack(webhook_url, text):
    payload = json.dumps({"text": text}).encode()
    req = urllib.request.Request(webhook_url, data=payload,
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=15) as resp:
        return resp.status == 200
```

### Image uploads via Slack Bot Token + slack_sdk

Incoming webhooks **cannot** upload files. For images:

1. Create a Slack app at https://api.slack.com/apps (from scratch)
2. OAuth & Permissions → add bot scopes: `files:write` and `chat:write`
3. Install to workspace, copy Bot User OAuth Token (`xoxb-...`)
4. Invite bot to channel: `/invite @bot-name`
5. Get channel ID: right-click channel → View channel details (bottom)

```python
from slack_sdk import WebClient  # pip install slack_sdk
client = WebClient(token="xoxb-...")
client.files_upload_v2(
    channel="C0123456789",
    file="annotated.jpg",
    title="Bird detection",
    initial_comment=":camera: Annotated image from YOLO",
)
```

The old `files.upload` was retired March 2025; use `files_upload_v2`.

## Secret management

Store secrets in a gitignored `secrets/` directory with `chmod 600`:

```
secrets/
├── webhook-url.txt      # Slack webhook URL (one line)
├── bot-secrets           # export SLACK_BOT_TOKEN="xoxb-..."
│                         # export SLACK_CHANNEL_ID="C0..."
├── <YOUR_SAGE_TOKEN_FILE>        # Sage portal access token (one line)
└── curl-example.txt      # Example curl with webhook
```

Resolution order: CLI flag → env var → secrets file.
Bot secrets: parsed from shell export lines in `secrets/bot-secrets`.

## COCO classes reference (YOLO)

80 classes. No "hand" class. Relevant for wildlife/outdoor monitoring:
- `bird` (#14) — hummingbirds, etc.
- `person` (#0) — whole person (useful for testing: wave at camera)
- `fork` (#42) — useful for testing (hold near feeder)
- `cat` (#15), `dog` (#16) — common backyard visitors
- `bottle` (#39), `cup` (#41), `vase` (#75) — feeder false positives at night
- `fire_hydrant` (#10) — another common IR false positive for feeders

## BioCLIP species enrichment

BioCLIP publishes species-level predictions:
- `env.species.<rank>` — top predicted taxon name (e.g. "Archilochus colubris")
- `env.species.<rank>.confidence` — confidence score (0-1)
- `env.species.top5` — JSON of top-5 predictions

Combine with YOLO: use YOLO as trigger ("bird detected"), BioCLIP for species ID. Correlate by timestamp in the watcher. BioCLIP always produces predictions (even for empty scenes), so use `--min-confidence 0.5+` to gate publishing.

### Watcher-side species query pattern

When a YOLO detection triggers, query BioCLIP's recent species predictions and include in the Slack alert:

```python
BIOCLIP_MEASUREMENT = "env.species.species"

def query_bioclip_species(vsn, start="-5m"):
    """Query recent BioCLIP species predictions. Returns {name, confidence} or None."""
    records = query_sage_data(vsn, BIOCLIP_MEASUREMENT, start=start, tail=5)
    if not records:
        return None
    latest = records[-1]
    species_name = latest.get("value", "")
    if not species_name:
        return None
    # Get companion confidence record
    conf_records = query_sage_data(vsn, "env.species.species.confidence", start=start, tail=5)
    confidence = float(conf_records[-1].get("value", 0)) if conf_records else None
    return {"name": species_name, "confidence": confidence}

# In detection handler:
species_info = query_bioclip_species(args.vsn)
# Include in Slack message:
if species_info:
    sp_conf = species_info.get("confidence")
    msg += f"\n:dna: BioCLIP species ID: *{species_info['name']}*"
    if sp_conf is not None:
        msg += f" ({sp_conf:.0%} confidence)"
```

## Watching multiple measurements

```python
DEFAULT_MEASUREMENT = "env.count.bird"
DEFAULT_EXTRA_MEASUREMENTS = ["env.count.person", "env.count.fork"]

# In the main loop:
all_measurements = [args.measurement] + DEFAULT_EXTRA_MEASUREMENTS
records = query_sage_data(args.vsn, all_measurements, start=lookback)
```

## Key design decisions

- **Cooldown** (default 5 min): prevent duplicate alerts for the same detection window
- **Lookback**: query slightly more than the poll interval to avoid missing records
- **Startup/shutdown messages**: post to Slack so the channel knows the watcher is active
- **Ctrl+C handling**: catch KeyboardInterrupt, post goodbye, exit cleanly

## Reference implementations

- **Hummingbird watcher**: `~/AI-projects/slack-hummingbird/` — polls for bird/person/fork from H00F, posts text + image to Slack. Pure stdlib polling, slack_sdk for images.
- **Wildfire trigger**: `github.com/waggle-sensor/wildfire-trigger-example` — adjusts job scheduling based on smoke detection
- **Severe weather trigger**: `github.com/waggle-sensor/severe-weather-trigger-example` — suspends/resumes jobs based on NWS API
