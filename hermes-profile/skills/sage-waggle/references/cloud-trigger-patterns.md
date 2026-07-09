# Cloud Trigger Patterns

This content has been consolidated into `references/cloud-trigger-notifications.md`, which covers:
- Architecture and polling patterns (no pip deps needed)
- Querying detections and uploaded images from the Sage data API
- Downloading images from Sage storage (curl -L, propagation delay)
- Slack text alerts (webhook) and image uploads (bot token + slack_sdk)
- Secret management conventions
- YOLO COCO class reference
- Official reference implementations (wildfire trigger, severe weather trigger, hummingbird watcher)
- Design decisions (cooldown, lookback, deduplication, startup/shutdown messages)

See that file for the complete reference.
