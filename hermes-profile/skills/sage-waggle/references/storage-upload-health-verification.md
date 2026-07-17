# Verifying Sage upload/storage health: record EXISTS vs file RETRIEVABLE

How to prove whether a Sage data-plane / object-storage bug (e.g. the NRP
storage-404 class, Infra #18) is actually LIVE right now — by comparing a Beehive
data-API `upload` record against the actual backing bytes. A record existing does
NOT mean the file landed; they are separate systems (metadata vs object store).

Verified 2026-07-08 re-checking Infra #18 on H00F bioclip uploads: 12/12 aged
files retrievable, 0% loss → bug was transient/leftover, not live. But the
investigation nearly produced a FALSE "still broken" conclusion twice, from
probing artifacts (below). Trust the method, not the first scary numbers.

## The two-system model (why a record can 404)
- `data.sagecontinuum.org/api/v1/query` serves the METADATA record (the
  `name="upload"` message with `value`=object URL). Fast, reliable.
- The `value` URL points at `storage.sagecontinuum.org`, which **302-redirects**
  to the actual object host: `nrdstor.nationalresearchplatform.org:8443`
  (NRP replica). The bytes live there, replicated downstream from Beehive uploads.
- Infra #18 = objects never replicate to NRP → permanent 404 on the redirect
  target while the metadata record looks healthy. "Record exists, bytes don't."

## The verification recipe (records → bytes)
1. Pull the latest image-upload records for the node/task:
   ```
   curl -s -X POST https://data.sagecontinuum.org/api/v1/query \
     -H 'Content-Type: application/json' \
     -d '{"start":"-40m","filter":{"vsn":"H00F","name":"upload","task":"<task>"}}'
   ```
   NB filter key is `task` (the job name, e.g. `bioclip-species-classifier`), NOT
   `job` and NOT `plugin` for the human name. `plugin` = the full
   `registry.../<name>:<ver>` tag. (See ref image-upload-provenance-and-linking.)
2. Auth to fetch bytes: `-u "beckman:$TOKEN"` where token file is
   `~/AI-projects/slack-hummingbird/secrets/sage-token.txt` (strip trailing
   newline: `tr -d '\n'`). Unauthenticated fetch → HTTP 401.
3. Probe each backing file:
   `curl -s -o /dev/null -w "%{http_code}" --max-time 30 -L -u "beckman:$TOK" "$url"`
   The `-L` is REQUIRED to follow the 302 to NRP.
4. Confirm real bytes on a 200: pipe to `file` — expect `JPEG image data …`.
   (Storage may mislabel `content-type: text/html`; the BYTES are what matter,
   not the header. A 640x360 JPEG at ~90 KB is the bioclip hummingcam shape.)
5. Verdict rule: classify each file 200 / 404 / other, EXCLUDING files younger
   than ~5 min (those may be propagation lag, not loss — see pitfall 3). If aged
   files (>5 min) 404 persistently → bug is LIVE. If all aged files 200 →
   transient/resolved.

## PITFALLS that fake a "still broken" result (all hit this session)
1. **grep|cut URL corruption.** Extracting URLs from a scratch TSV via
   `grep <ts> | cut -f2` can split on the wrong field and hand curl a bare
   nanosecond timestamp as a hostname → `curl: (6) Could not resolve host:
   1783470056913181232` → HTTP 000. This looks like a storage outage; it's a
   shell bug. ALWAYS derive URLs straight from the JSON record `value` (parse in
   Python), never from re-greps of intermediate files.
2. **Tight-loop rate-limit → HTTP 000.** Hammering NRP :8443 with rapid
   sequential requests (no spacing) trips a connection cap; curl returns 000
   (couldn't connect) even for files that ARE present. Space probes ≥2-4 s apart.
   A file that 000s in a tight loop but 200s five-times-clean at 4 s spacing is
   PRESENT — the 000 was the probe, not the file. Distinguish: 000 at
   `time_total≈0.001s` = connect/DNS failure (your bug or rate-limit); a real 404
   returns a small JSON body (~194 B) with a normal round-trip time.
3. **Propagation lag ≠ loss.** Freshly-uploaded objects legitimately 404 for a
   couple minutes before replicating to NRP, and they can land OUT OF ORDER (a
   newer file present while an older one still 404s). This is normal replication
   latency, categorically different from #18 (permanent). Only judge files that
   are already >5 min old. Watch a "missing" file go 404→200 over a few minutes to
   confirm it was lag.

## Robust probe pattern (avoids all three)
- Parse records with Python; use `r["value"]` directly (no grep/cut).
- Compute each record's age; keep only age ≥ 300 s for the loss verdict.
- Probe sequentially with `time.sleep(2)` between requests, `--max-time 30 -L`.
- Report `200 / 404 / other` counts + an explicit miss-rate %. A reusable script
  lives at `scripts/query-data.py` for the query side; the byte-probe loop is
  small enough to inline (see the recipe above). If you background a long census,
  spacing + `--max-time` keep it from hanging the foreground (60 s cap).

## Diagnosing the ON-NODE ship stage (upstream of the data API)
Before a file can become a data-API record it must be SHIPPED off-node by the
`wes-upload-agent` DaemonSet. When a plugin logs "uploaded" but nothing appears in the
data API, the break may be HERE — not your code, not NRP storage. Diagnose on the node
(VSN-prefixed SSH, e.g. `ssh USER@node-<VSN>.sage`):
1. **File still staged?** Look for FILES, not dirs:
   `sudo find /media/plugin-data/uploads/<Job>/<task>/<version>/ -type f` (leaf shape
   `[<job>/]<plugin>/<version>/<ts>-<sha1>/{data,meta}`). Empty leaf/parent dirs left
   after a ship are NORMAL — checking dirs gave a FALSE "STILL_STAGED" this session.
2. **Read `meta`** — proves producer identity (`vsn`,`node_id`,`filename`,`task`) even
   before the ship lands (e.g. injected-env `vsn=H00F`).
3. **Agent log** `sudo kubectl -n default logs <upload-agent-pod> --tail=N`:
   healthy = `uploading: ./<path>`→`done:`→`cleaning up:` at ~MB/s. BROKEN = `Authenticated
   to beehive-upload-server` then `rsync hasn't made progress in 15s... sending
   interrupt!` each cycle + `rm: can't remove '/tmp/rsync_healthy'`; a high RESTARTS
   count (saw 154) corroborates chronic ship failure.
4. **Verdict — separate "my code" from "node can't ship":** if the staged `{data,meta}`
   exist with correct meta, the `data` EXIF/content is right, and the agent logs
   `uploading: ./<your path>` + auth SUCCESS but then the rsync STALL → the PRODUCER
   side is PROVEN; the gap is node upload-health (report to infra). Auth/DNS OK while
   bulk transfer stalls = node↔Beehive throughput/MTU/server-side issue, not your change.
5. Once the agent is healthy, a re-run ships clean and the object appears in the
   data-API query (allow sub-5-min propagation lag above).

### PITFALL: agent SILENTLY skips a bad version path-segment
The agent's `find` only selects staged dirs whose `<version>` segment matches
`x.y.z | vx.y.z | latest | test`. `pluginctl run <image>` takes that segment from the
IMAGE TAG, so a dev tag like `:gate3` → `.../<plugin>/gate3/<ts-sha>/` is REJECTED: the
file stages, the plugin logs "uploaded", the agent never ships it (log shows "uploaded
all files found" while your dir sits). Fix: retag `:test` (or real `x.y.z`) and re-run.
Also in `pluginctl-sideload-and-node-build`.

## One honest caveat to always state
Even when the verdict is "resolved," note the residual sub-5-min propagation lag
exists — it is normal and NOT #18. Keep the #18 tracker entry as historical
record of the 2026-06-18 outage; mark it resolved with the dated re-verification
rather than deleting it.
