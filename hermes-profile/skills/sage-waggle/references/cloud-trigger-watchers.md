# Cloud-trigger watchers (external poll → notify)

The Sage "cloud trigger" pattern: a script runs OFF the node (laptop/server),
polls the public Sage data API for a measurement, and acts (Slack/email/etc.)
when a condition is met. See waggle-sensor/wildfire-trigger-example and
severe-weather-trigger-example for the canonical shape. This file captures
non-obvious production lessons.

## 1. Object-store propagation lag — the "detected but no photo/clip" trap

THE SINGLE MOST IMPORTANT GOTCHA. The Sage object store
(storage.sagecontinuum.org) is cross-country and uploads propagate through
caches ASYNCHRONOUSLY. The `upload` RECORD lands in the data API
(data.sagecontinuum.org) a beat before the actual BLOB is readable from
storage, and full propagation can take **up to ~2 minutes**.

Symptom: a watcher detects an event, sees the `upload` record, fetches the
image/clip URL immediately, and gets **HTTP 404/5xx → curl exit 22**. The media
is dropped permanently even though the same URL downloads fine minutes later.

WRONG fix: a few retries spaced 2s apart — useless against a 2-minute lag.
WRONG fix: blocking the poll loop with a long sleep — stops watching, serializes.

RIGHT fix — DEFERRED RETRY QUEUE (non-blocking):
- Post the text/alert IMMEDIATELY on detection (don't make the user wait for media).
- ENQUEUE the media fetch: `{url, detected_ts, enqueued_at, attempts}`.
- Each poll cycle, run a queue processor that:
  - skips items younger than a first-attempt delay (~20s, let the blob start propagating),
  - tries the download once per cycle for eligible items,
  - on success posts the media as a FOLLOW-UP message and dequeues,
  - on failure leaves it queued for the next cycle,
  - DROPS items past a deadline (~240s / 4 min) with an explicit log so the queue
    can't grow unbounded.
- With a 60s poll cadence this yields ~3–4 attempts over ~4 min for free.
Reference impl: slack-hummingbird `process_image_queue()` (commit 1c48281).

Always capture the HTTP status on download failures for triage:
`curl -s -f -L -w "%{http_code}" ...` then log "HTTP <code>" instead of bare
"curl exit 22". exit 22 = HTTP >= 400 (because of `-f`).

## 2. Deploy as a systemd USER service, not tmux

A watcher run as a bare `python3` in tmux silently dies on reboot / closed
terminal and stays dead (observed: silent for days). Use a systemd USER service:

- Unit at `~/.config/systemd/user/<name>.service`, `Restart=always`,
  `RestartSec=15`, `Environment=PYTHONUNBUFFERED=1`, logs to journal.
- `StartLimitIntervalSec` / `StartLimitBurst` go in **[Unit]**, NOT [Service]
  (systemd silently ignores them in [Service] → "Unknown key name" warning).
- Requires `loginctl enable-linger <user>` so it runs without a login session
  and starts at boot. Verify: `loginctl show-user <user> | grep Linger`.
- Manage: `systemctl --user {enable,start,status,restart} <name>`; follow logs
  `journalctl --user -u <name> -f`. For `systemctl --user` over SSH/non-login
  shells, export `XDG_RUNTIME_DIR=/run/user/$(id -u)` first.
- Crash-recovery test: `kill -9` the MainPID, wait > RestartSec, confirm a new
  PID and `is-active` = active.

## 3. Trigger-coverage gap: YOLO count vs BioCLIP species

On the hummingcam, the watcher historically triggered ONLY on YOLO
`env.count.bird > 0`. But YOLO (object detector, needs a clear largish bird)
misses tiny/fast hummingbirds that BioCLIP (whole-image classifier) confidently
IDs. Measured 24h gap: `env.count.bird` fired ~15× while BioCLIP logged ~156
confident species + 156 image uploads. So a YOLO-only watcher misses ~90% of
what shows in the portal.

Better trigger: an INDEPENDENT BioCLIP path that fires on
`env.species.species` confidence ≥ threshold, gated by a species ALLOW-list
(e.g. hummingbird genera Archilochus/Selasphorus/Calypte) to exclude night-time
false positives (flying squirrels Glaucomys/Petaurista, civet Paguma — BioCLIP
zero-shot has no reject class so it over-confidently labels empty/animal frames).
Keep the YOLO path too; share cooldown + dedup-by-timestamp across both.

## 4. Finding the right upload to fetch

`query_latest_upload` filters `name="upload"` records by plugin pattern AND
`"annotated" in meta.filename` (yolo names files `http-snapshot-annotated.jpg`).
The `value` field is the full storage URL; `meta.filename` is the basename.
Download auth = curl basic auth `-u beckman:<sage-token>` (portal token, expires).
