# Decoupling "publish" from "save" in inference plugins (`--save-match`)

A reusable pattern for Sage camera/audio inference plugins (bioclip, birdnet,
yolo). Proven on H00F: bioclip-species-classifier 0.4.0.

## The problem it solves

A single `--min-confidence` threshold doing double duty — gating BOTH topic
publishing AND media upload — is a bad design. The two have very different costs:
publishing a topic is a few bytes; uploading an image/audio clip is tens to
hundreds of KB and is the real edge constraint (bandwidth + Beehive storage).
A blunt threshold can't express "save only the Barn Owls but report everything."

## The pattern

Split into two strictly separate code paths per cycle:

- **PATH 1 — PUBLISH (always).** Publish the per-detection topics for everything
  above `--min-confidence` (the *reporting floor*), PLUS an always-on
  summary/heartbeat datapoint EVERY cycle even when zero detections clear the
  floor. The heartbeat proves the plugin ran (distinguishes "running, nothing
  seen" from "job dead"). `--min-confidence` now means ONLY the publish floor.
- **PATH 2 — SAVE (selective).** Upload the media artifact ONLY when a published
  detection matches a `--save-match` rule. This is the ONLY path that saves media.

### `--save-match` grammar (single delimited string — visible verbatim in logs)

```
--save-match "Barn Owl:0.5,Northern Cardinal:0.7"   # OR-list of Name:confidence
--save-match "*:0.7"                                  # wildcard: save anything >=0.7
```
- rules separated by `,`; name/confidence separated by `:` (rpartition on last
  `:` so scientific names with spaces work; names with `:` unsupported).
- name matched **case-insensitively + EXACTLY** (no substring) against the
  candidate names the caller supplies per detection: common OR scientific for
  bioclip/birdnet at the published rank; COCO class name for yolo.
- `*` is the only wildcard. Save fires if ANY detection matches ANY rule →
  upload the whole clip/frame ONCE.
- **omit `--save-match` = save nothing** (opt-in media saving; topics still flow).

### Key design decisions (locked)
- `--save-match` operates on PUBLISHED detections only (single floor, Model A). A
  rule threshold below `--min-confidence` is effectively raised to the floor —
  document "to save a low-confidence species, lower --min-confidence."
- Save the ANNOTATED image (bioclip/yolo); for audio, the captured clip.
- Match is rank-aware: a Species rule on a `--rank Order` job never matches —
  warn loudly in ECR docs.
- BEHAVIOR CHANGE on upgrade: a job bumped to the save-match version withOUT a
  `--save-match` arg keeps publishing topics but STOPS uploading media. Migrate
  existing jobs by adding `--save-match "*:<old-min-confidence>"` to preserve the
  prior "upload high-confidence frames" behavior.

## Implementation shape (dependency-free, copy-per-repo)

A small `save_match.py` module — `parse_save_match(spec) -> [Rule]` (fail-fast,
raises on malformed rule / out-of-range confidence) and
`should_save(rules, detections, name_keys) -> bool`. The three plugin repos do
NOT share a Python package, so the module is COPIED identically into each (with a
TODO to refactor to a shared package later). Ship a pure-Python unit test
(`tests/test_save_match.py`) that runs both via pytest AND a dependency-free
`if __name__=="__main__"` runner, so it passes on a node with no pytest:
`python3 tests/test_save_match.py`.

Wire `--save-match` parsing at startup and FAIL FAST (log + `raise SystemExit(2)`)
on a bad spec — a typo'd rule that silently saves nothing would waste a whole
deployment. Add `COPY save_match.py .` to the Dockerfile next to `COPY app.py .`.

## Verifying the deploy (BOTH paths)

Scheduler "Running" is NOT proof. Verify in the data plane:
- **Negative path:** on quiet cycles, the heartbeat/summary topic appears every
  cycle (tag = new version) and `upload` count == 0. Easy to confirm any time.
- **Positive path:** wait for a real detection >= a rule's threshold (e.g. a
  daylight bird) and confirm an `upload` record lands with matching
  `meta.top_species`/`meta.confidence`. Don't declare done on the negative path
  alone — prove a save actually fires.

For camera plugins, time verification to the science-rule cron window. If you
submit AFTER the cron minute (e.g. job fires `'20 * * * *'` but you submitted at
:22), this hour's window is missed — next launch is next hour. That's expected,
not a failure.

## DATA-API FILTER TRAP — `meta.task`, NOT `meta.job`

When querying `data.sagecontinuum.org/api/v1/query` to verify, plugin records key
the job/task NAME under **`meta.task`** (e.g. `"insect-bioclip"`), NOT `meta.job`.
`meta.job` does NOT exist on these records — filtering/grouping on it silently
yields `job="?"` and ZERO matches, which looks exactly like "the deploy is
publishing nothing" when in fact the data is flowing fine. This trap cost ~3
false-alarm rounds in one session (and is the same mis-scoped-filter class that
bit the birdnet debugging). The plugin VERSION is the tail of `meta.plugin`
(`registry.sagecontinuum.org/<ns>/<name>:<VERSION>`). Other meta keys present:
`camera, host, node, rank, vsn, zone`. Always group by `meta.task` + `meta.plugin`
tail, and when a query returns 0, FIRST re-query with no task filter and inspect
the raw `meta` keys before concluding the plugin is broken.

## Other gotchas seen this session
- The node's Sage portal token expires; symptom is ECR API `HTTP 401 "Token not
  found"` / "could not parse Authorization header". Fix: re-copy a fresh token
  from portal.sagecontinuum.org into the token file (write with NO trailing
  newline — a trailing `\n` corrupts the `Authorization: Sage <tok>` header).
- An incremental rebuild is fast: with the model-download layer cached, only the
  `COPY save_match.py` + `COPY app.py` layers rebuild. The slow part is the
  `docker save | k3s ctr images import` sideload of the ~28 GB image (~8 min) —
  always background it with completion notification.
