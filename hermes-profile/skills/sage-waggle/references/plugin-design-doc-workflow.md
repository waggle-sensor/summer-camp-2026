# Design-doc-first workflow for non-trivial Sage plugin features

How Pete wants non-trivial plugin work done: a reviewable design note is written
and iterated to consensus BEFORE code. This governs the whole class of "design a
new/forked plugin" tasks (e.g. image-sampler2). Encodes the process, the commit
ritual, and the doc-hygiene technique — not any one plugin's decisions. Covers
both the initial creation/scrub of a doc AND the pre-externalization
COHERENCE-REVIEW pass before a doc becomes an upstream RFC (see that section for
the A/B/C finding taxonomy + the project doc-geography map).

## When this applies
- Any non-trivial feature/plugin: write a design note (decisions + open questions
  + staged plan) to `docs/` FIRST, get review, THEN implement in stages.
- Skip only for genuinely small one-offs. When in doubt, write the note.

## The per-edit review protocol (Pete's explicit workflow)
Pete reviews the design line-by-line and proposes changes conversationally. For
EACH proposed change:
1. REVIEW the idea first. If it might be a poor choice, RAISE the concern and HOLD
   OFF editing until confirmed. If it's sound, apply it.
2. Surface design questions/tradeoffs EXPLICITLY rather than silently picking —
   especially anything with real second-order effects. Pete wants pushback and
   tradeoff discussion, not a rubber stamp.
3. When you must make an interpretive call, FLAG it as an OPEN item in the doc for
   Pete rather than deciding silently.
Label locked decisions in-doc as `DECISION (Pete, YYYY-MM-DD): ...` with the
rationale, so later readers know it's settled and why.

## The commit ritual (do ALL of these in ONE commit per change)
Code + version + docs + CHANGELOG + jobs move together. After each doc/code change:
1. Edit the canonical doc in the repo: `docs/<plugin>.flint.analysis.txt`.
2. Add a `[Unreleased]` entry to `CHANGELOG.md` (Keep a Changelog; group
   Added/Changed/Fixed/Removed/Deprecated/Security).
3. Mirror the doc: `cp docs/<doc> ~/AI-projects/<doc>` (Pete keeps a working
   mirror outside the repo).
4. `git add` doc + CHANGELOG, commit with a descriptive multi-line message,
   `git push origin main`.
5. VERIFY: `git rev-parse HEAD` == `git ls-remote origin -h refs/heads/main`, and
   `md5sum` the canonical vs the mirror (must match). "Pushed" is not proof; the
   md5/rev parity is.

### Cutting a version (release commit) — reconcile sage.yaml inputs with the CLI
When bundling accumulated `[Unreleased]` work into a release version, do ALL of
these in ONE commit + an annotated tag, and treat `sage.yaml` as first-class:
1. Bump `version:` in `sage.yaml` (e.g. 0.1.1 -> 0.2.0). ECR won't rebuild an
   already-registered version, so the bump is what forces a fresh build.
2. **RECONCILE `sage.yaml`'s `inputs:` list against the ACTUAL CLI — it drifts
   stale silently.** Nothing enforces inputs↔flags parity, so a flag RENAME or
   ADD leaves the manifest wrong (real incident cutting image-sampler2 0.2.0:
   `inputs:` still listed `cache-dir` months after the CLI renamed it to
   `cache-root`, and was missing `cache-max-count`/`cache-max-mb`/`from-cache`/
   `node-id`). Regenerate the truth from the binary:
   `python3 app.py --help | grep -oE '^\s+--[a-z-]+' | tr -d ' ' | sort -u`
   then make each real flag an `inputs:` entry with the right type
   (bool/int/float/string). A stale manifest mislabels the deploy form users see.
3. Move the `[Unreleased]` CHANGELOG entries under a `[x.y.z] - YYYY-MM-DD`
   heading with a one-paragraph feature summary; leave a fresh empty
   `[Unreleased]` on top.
4. Release GATE before committing: run the full test suite (it must pass) and grep
   `sage.yaml` to confirm `^version` is bumped and no renamed-away flag lingers.
5. Commit code+version+docs+CHANGELOG together, then `git tag -a vX.Y.Z -m '...'`,
   `git push origin main`, `git push origin vX.Y.Z`. VERIFY the tag landed on the
   remote: `git ls-remote --tags origin vX.Y.Z` (pushing main does NOT push tags).
6. Mirror-sync convention: only `cp` the analysis-doc mirror if the doc CHANGED
   this commit (`diff -q` first) — a version cut usually touches only
   sage.yaml/CHANGELOG, so the mirror is often already in sync; don't re-copy
   needlessly.
Note: `--plugin-version` default in app.py can stay `<plugin>:dev` (env-overridable
`IS2_PLUGIN_VERSION`); the real version is injected at deploy time, so it does NOT
need bumping alongside sage.yaml.

### Pitfall: spurious "modified by sibling subagent" warning on CHANGELOG/doc
The `patch`/`write_file` tools intermittently warn that
`~/AI-projects/image-sampler2/*` was "modified by sibling subagent … but this
agent never read it" — a STALE false-positive from Hermes file-tracking left over
from earlier parallel-agent activity on this repo, NOT real contention. Do NOT
abort the commit. Instead verify: `git status --short` shows ONLY your intended
files, and `git diff --stat` matches the change you made. If so, the edit merged
cleanly — proceed to commit. (Also recorded in memory.)

## Scrubbing an accreted design doc (high-value technique)
An iteratively-refined doc grows in TWO layers that drift into contradiction:
(L1) the original upstream/as-is study + early "future ideas," and (L2) the later
LOCKED decisions. Early ideas get SUPERSEDED by later decisions but the stale text
is never removed → dangling references ("see pitfalls" with no pitfalls section),
"add feature X" that was later decided AGAINST, "fix Y" that was already designed
out. When asked to clean it up:
1. Read the WHOLE doc end to end first; catalog every contradiction/dangling ref
   before editing (don't spot-fix).
2. Copy to `<doc>2.txt`, do a COMPLETE rewrite, leave the original untouched until
   the user approves the swap. Then `cp` over the canonical, `rm` the temp
   (`git mv` fails on an untracked temp — just cp+rm), re-sync mirror, commit.
3. Restructure into a STATUS-TAGGED shape with a legend at top:
   `[LOCKED] [VERIFIED] [REQUIREMENT] [OPEN] [DEFERRED]` (+ inline `[SUPERSEDED
   by N.N]`). Parts: (1) upstream study — preserve every VERIFIED empirical
   finding intact; (2) locked design; (3) requirements carried forward (promote
   still-valid old "ideas" from a loose list to explicit REQUIREMENTS); (4)
   genuinely open items; (5) deferred enhancements.
4. Reclassify every stale bullet as FIXED-in-design / DECIDED-against / RESOLVED /
   ADOPTED-as-requirement / DEFERRED — no orphan "future work" that's already
   settled.
5. Preserve, don't re-litigate: reorganizing must not drop a verified finding or a
   locked decision.
5b. STRIP superseded-draft archaeology once a decision is settled — this is a
   distinct cleanup Pete asks for explicitly ("the document does not need to
   discuss revisions that were superseded"). REMOVE: rejected-alternative lists
   ("Rejected: Option A = lossy, B = ..."), option-label cruft ("Option C
   (HYBRID)", "Opt-4"), and internal draft question-IDs that are defined nowhere in
   the final doc ("Q0 RESOLVED:", "(Q2 RESOLVED)"). KEEP: legitimate design
   RATIONALE that explains why the chosen approach is correct (e.g. "Rejected:
   `capture(); sleep(N)` drifts" — that justifies the algorithm, it's not history),
   upstream->new migration mappings ("was --cronjob", "renamed from --out-dir"),
   and Part-1 defect->where-addressed tags (they're forward navigation). Rule of
   thumb: remove "here's what we used to think / what we rejected"; keep "here's
   why the current choice is right" and "here's how to migrate from upstream."
   After stripping, re-sweep that all section cross-refs still resolve.
6. Number sections in ARABIC (1.1, 4.2), not Roman — Pete's preference; Roman
   sub-refs (IV.4) are awkward. If converting, sweep the WHOLE doc incl. the intro
   and parenthesized `(I)..(V)` lists (a regex keyed on `roman + .digit` misses
   bare parenthesized ones).
7. Add a single MODE/FLOW OVERVIEW block that states each invocation's data flow
   in one place, then cross-reference it from the per-flag sections, so the logic
   is unambiguous and consistent across touchpoints.

## Pre-externalization COHERENCE-REVIEW pass (a design doc → upstream RFC)
Distinct from the full "scrub an accreted doc" rewrite above. When a doc is
already clean but grew via many piecemeal edits and is about to go EXTERNAL (an
upstream RFC to waggle-sensor/pywaggle, or a CI-team conversation), Pete wants a
whole-doc coherence pass — NOT a rewrite. He picked this over "turn it into an RFC
now" and "start implementing," so: polish for coherence FIRST, before the doc
leaves the building. Method that worked on pywaggle2-design.md:
1. READ the entire doc end-to-end in this session (don't trust the piecemeal
   memory of prior edits — a doc assembled over N sessions drifts in ways only a
   single continuous read surfaces). Batch the reads.
2. Catalog findings into a THREE-TIER taxonomy and present them BEFORE touching the
   file (Pete reviews findings, then greenlights the edit batch — same
   review-before-edit protocol as line edits):
   - (A) INCONSISTENCIES / stale bits: an object referenced but never named; two
     sections describing the same field differently; a section intro that no longer
     matches its (later-expanded) contents.
   - (B) GAPS A REVIEWER WILL ASK ABOUT — the highest-value tier. Lens: "what is
     the FIRST question an upstream maintainer raises?" For an API doc that's
     almost always the ERROR/EXCEPTION CONTRACT (what does the call do when it
     fails — raise? return None? partial?), then thread-safety/cache-scope of any
     stateful accessor, then the shape of any API NAMED but not specified.
   - (C) NITS: redundancy, a missing status/next-step footer.
3. Fix A + B substantively; do C only if cheap. Every edit should be ADDITIVE or
   CLARIFYING — a coherence pass must NOT change the design, only close the
   questions a first external reader would raise. Say so explicitly in the summary
   ("design unchanged; N clarifying edits").
4. Name the anonymous. If §X exposes `NodeInfo` but §Y refers to "the snapshot
   object," give the latter a parallel name (`Snapshot`) and use it consistently.
5. Add a §"Status & next step" footer pinning the time-critical move — e.g. "the
   CI team is finalizing their GPS/VSN identity API, so circulate §2 with them
   BEFORE it freezes so pywaggle2 WRAPS rather than COMPETES." An RFC that names
   the external clock is more actionable than one that ends on open questions.
6. After editing, re-grep the header outline (`grep -nE '^#{1,3} '`) to confirm
   section order/numbering survived, and update the size/one-line description in
   `~/AI-projects/project-status.txt` (the doc-inventory map) so it stays accurate.

Doc geography for this project (so a resumed session doesn't rediscover it):
`~/AI-projects/project-status.txt` is the MAP of all design/tracker docs.
`pywaggle2-design.md` = the next-gen client-library RFC (acquisition ladder +
node-info/mobility + library enhancements); `local-cache-design.md` = its Layer-2
companion (the shared /local-cache + wes-local-cache-manager DaemonSet, built &
running on H00F at v0.1.0). The two AUTHORITATIVE trackers are
`Infra-problems-to-fix.md` (outside plugins) and `plugin-improvements.md` (inside
our plugins); everything else is DESIGN/RFC or SUPERSEDED. Resume such work with
`session_search` first, then read project-status.txt to re-anchor.

## Staging the implementation (after the design note is approved)
Once the doc is locked, Pete wants "very careful, step-by-step, small VERIFIED
steps, each achieving a couple interlinked features." How to group them:

GROUPING PRINCIPLE: each stage ends with an artifact you can VERIFY in the data/
host plane — a file on disk with the right name/EXIF, or a record in Beehive.
"It runs" is never the proof. Group the smallest set of features that together
produce something observable end-to-end; ship interlinked features together only
when one is meaningless to verify without the other (e.g. capture-ts naming + EXIF
both need a real saved frame, so they're one stage). Build the self-proving
skeleton first, then layer onto a working spine. Defer anything needing a second
pod / the shared mount until the single-plugin path is solid.

A proven staging for a producer/consumer image plugin (image-sampler2):
- Stage 0: repo skeleton + CLI contract + fail-fast validation, NO capture.
- Stage 1: single real capture -> save raw bytes (proves the camera dependency
  in isolation; run on the actual node).
- Stage 2: capture-ts + vN naming + EXIF embed (the "self-describing file"
  bundle — the three are one feature viewed three ways; verify by reading EXIF
  back off the saved frame).
- Stage 3: --one-shot upload path (first Beehive record — strongest verification).
- Stage 4: --continuous fixed-period loop + ring cache (loop + eviction are
  inseparable).
- Stage 5: continuous heartbeat (depends on the ring existing).
- Stage 6: --from-cache + self-exit (needs a populated cache AND the upload path).
- Stage 7: shared-cache placement + packaging/ECR (make it deployable/consumable).
Spine: 0->1->2->{3,4}->5->6->7. Deferred items (discovery, time-window selectors,
unresolved OPEN decisions) are NOT build stages.

## Spike-before-build: resolving an OPEN design item with a verified experiment
When a stage depends on an unresolved OPEN item (a library choice, an API behavior,
a permission model), insert a small SPIKE step BEFORE that stage rather than
guessing inside it — Pete asks for this by name ("let's sort out X"). Pattern:
1. Write a THROWAWAY script that answers the exact question with pass/fail CHECKS
   on a realistic input (e.g. does piexif preserve foreign JPEG segments + avoid
   re-encode? — checks: foreign COM survives, SOS..EOI byte-identical, JSON+SHA256
   round-trip, negative-GPS handled). Make each check a printed boolean; exit
   nonzero if any fails. Ground claims in the actual library source when useful
   (read the function, don't trust the README) — this surfaces API quirks the docs
   omit.
2. Run it; capture the empirical result. The DELIVERABLE is a decision, not just a
   green run.
3. Record the decision back into the design doc's OPEN item: flip it
   `[OPEN]` -> `[RESOLVED YYYY-MM-DD]` in place (keeps section numbers stable for
   cross-refs), naming the choice AND the gotchas learned (so the implementing
   stage doesn't rediscover them the hard way).
4. KEEP the spike in the repo under `spikes/<name>.py` as reproducible evidence
   even though it's throwaway from the product path — future work
   reproduces-with-modifications when validating the same class for a new
   plugin/camera. Add any new runtime dep it proved to `requirements.txt` at the
   consuming stage.

STAGE 0 PATTERN (do this first, it's pure and hardware-free): make the CLI a
unit-testable contract before any I/O.
- Factor into three functions: `build_parser()` (returns the argparse parser so
  tests construct it in isolation), `validate_args(args)` (PURE — raises a custom
  `ConfigError`, never calls exit(); tests catch the exception), and `main(argv=
  None)` (parse -> validate -> in Stage 0 just print the validated config + exit 0;
  later stages wire real work here). `main` takes `argv=None` so tests drive it
  in-process.
- Use `add_mutually_exclusive_group(required=True)` for the mode; let argparse
  enforce required+exclusive+type, and put CROSS-flag rules (flag X only valid in
  mode Y, X requires Y, existence/writability of a dir, filesystem-safe name) in
  `validate_args`.
- Distinct exit codes: config error = a specific nonzero (e.g. 2) so a scheduler
  can tell "invoked wrong" from a runtime failure.
- Tests: pure pytest over the real parser+validator, one case per bad combo
  (assert `ConfigError`/`SystemExit` + a message substring) and per good combo.
  Skip a not-writable-dir test when running as root (root ignores the write bit —
  `if os.access(dir, os.W_OK): pytest.skip("root")`). Then ALSO run a few real
  subprocess invocations to confirm the shebang/`sys.exit` path returns the right
  codes (in-process `main()` tests don't exercise that).
- Commit ritual for CODE stages: this is the code path, so there's NO analysis-doc
  mirror to sync — just CHANGELOG (+ `### Added` for a new stage) + the code +
  tests in one commit; verify local==remote. Add a `.gitignore` early (venv,
  __pycache__, .pytest_cache, sample.jpg) so test artifacts don't get committed.
- Document the new flags in `ecr-meta/ecr-science-description.md` as part of the
  stage that introduces them: a mode table, then a per-flag list (what each does +
  which mode it belongs to), a fail-fast rules section, and usage examples. Pete
  asks for this explicitly ("clear ecr-meta documentation of the new CLI flags").

## Executing a LATER code stage (Stage 2+): sub-staging + testable architecture
Stage 0/1 patterns above are for the CLI/acquisition spine. A bigger later stage
(e.g. Stage 4 = continuous loop + ring cache) is best broken into SUB-STAGES, each
its own commit with tests + CHANGELOG, building inward-out (pure core first, wiring
last). A proven sub-staging for "continuous producer + ring cache" (image-sampler2
Stage 4), reusable for any loop-drives-a-local-sink feature:
- **4a — PURE core module first (`cache.py`), zero I/O deps.** No camera, no
  network, no pywaggle — filesystem only. This is where the ring logic
  (`resolve_cache_root`/`scan_ring`/`plan_evictions`/`commit_capture`) lives, so it
  gets EXHAUSTIVE unit tests over tmp dirs (every cap combo, eviction ordering, E3
  guard, atomic-publish, adoption, fail-soft delete). Pure functions =
  trivially-testable = the bulk of the coverage lands here, before any wiring.
- **4b — factor the SHARED body so two modes emit IDENTICAL bytes.** Both
  `--one-shot` (upload) and `--continuous` (ring) must produce the same
  name/EXIF/bytes → extract one `capture_and_embed_to_tmp()` (grab→embed→fsync'd
  `.tmp`) used by BOTH. Refactor the EXISTING mode to call it FIRST; the existing
  Stage-3 tests are your behavior-preserving GATE (they must stay green with the
  return-shape unchanged). Do the refactor as its own commit before adding the new
  caller, so a regression is attributable.
- **4c — wire the loop + do the CLI rename/rework.** Compose 4a+4b under the
  scheduler; this is where CLI breaks (rename a flag, make required→optional,
  add a fail-fast rule) land, WITH the Stage-0 tests updated in the same commit.
- **4d — on-node verification** (deferred until Pete supplies creds / green-lights
  touching the node). See `references/on-node-verification-recipe.md` for the
  build→side-load→run→data-plane-confirm→teardown recipe (incl. the
  host-mounted-cache producer trick and the Beehive query for records/uploads).

### Testable-loop architecture (inject the clock, don't sleep for real)
A `--continuous` scheduler must be unit-testable without wall-clock waits:
- Make the loop a standalone function `run_capture_loop(*, interval_s, do_capture,
  max_ticks=None, monotonic=None, sleep=None)` — inject the clock + sleep + the
  capture action; `max_ticks` bounds it for tests (None = forever in prod). A
  `FakeClock` (monotonic_ns counter; `sleep()` advances it) then deterministically
  proves fixed-grid firing AND skip-on-overrun (make `do_capture` advance the fake
  clock past N to simulate an overrun; assert the next fire lands on the next
  FUTURE grid slot).
- **PITFALL (cost me a 60s hang): a default arg `sleep=time.sleep` binds the REAL
  function at def-time, so `monkeypatch.setattr(app.time, "sleep", ...)` does NOT
  take effect** — the loop sleeps for real (interval×ticks). FIX: default the
  params to `None` and resolve `sleep = sleep or time.sleep` INSIDE the function
  (looked up at call time), so both explicit injection AND module-level
  monkeypatching work. Same for `monotonic`.
- The scheduler must NOT swallow exceptions — keep it a thin timing loop and put
  the fail-soft try/except in the `do_capture` closure (the loop's contract is
  "do_capture never raises"; test that contract both ways).

### Adding a SECOND grid to an existing loop (e.g. a heartbeat) — two traps
When a later stage adds an independent cadence to a loop that already has tests
(image-sampler2 Stage 5: a `--heartbeat-secs` grid alongside the capture grid),
DON'T mutate the proven `run_capture_loop`; write a new `run_dual_grid_loop` that
sleeps to the NEAREST of (next capture edge, next heartbeat edge) and fires
whichever grid(s) are due on wake. This keeps the heartbeat on its own cadence
even when sampling is much slower (a slow timelapse still reports alive ~60s),
while never emitting >1 beat per slot. Two traps bit me swapping the wiring:
- **max_ticks SEMANTICS SILENTLY CHANGE.** The old single-grid loop did one
  capture per iteration, so `max_ticks` == "N captures." A dual-grid loop wakes on
  EITHER edge, so counting wake-iterations != captures — the existing tests' bound
  now means something different and their count assertions break. FIX: give the new
  loop TWO bounds — `max_iters` (wake iterations) AND `max_captures` (do_capture
  calls, the natural producer bound) — and have the caller pass `max_captures` so
  the old "stop after N captures" contract is preserved.
- **A no-op-sleep fixture STARVES a grid-driven loop.** The Stage-4 tests patched
  `app.time.sleep` to a no-op WITH the real monotonic clock — fine for the old loop
  (it captured every iteration regardless of the grid), but the dual-grid loop only
  captures when a grid edge arrives, so with a frozen real clock + no-op sleep it
  spins forever without ever advancing to the next edge (60s hang). FIX: migrate
  those tests to a `FakeClock` whose `sleep()` ADVANCES virtual time, and thread
  `monotonic`/`sleep` injection down through `_continuous_to_cache` → the loop. Any
  loop whose progress depends on time passing needs a clock that moves on sleep,
  not a no-op sleep.
- Fire the heartbeat BEFORE the capture on a shared edge so an immediate startup
  beat lands first (count=0 == "I came up"). Keep the beat's grid logic in a pure
  helper (`Heartbeat` with `due(now)`/`next_due_ns(now)`/`record_capture()`/
  `snapshot_and_reset()`, accumulators reset each beat) so slot math + delta
  semantics are unit-tested with a FakeClock, no I/O. A long stall must emit exactly
  ONE catch-up beat, never a burst.
- End-to-end proof BEFORE on-node: stand up an in-process mock HTTP server
  (`http.server` on port 0) that serves a tiny real JPEG at the vendor snap path,
  point the real `_continuous_to_cache` at `127.0.0.1:<port>` with a no-op sleep +
  `max_ticks`, and assert on-disk ring state (bounded count, oldest evicted by
  ts-prefix, EXIF reads back, no `.tmp` litter, password redacted in the logged
  URL). This exercises the whole real path (acquire→embed→ring) with no camera and
  no node — the strongest verification available off-node.

### Stage 6 sub-staging: a CONSUMER/uploader that reads the cache (`--from-cache`)
The consumer half of a producer/consumer plugin (image-sampler2 Stage 6:
`--one-shot --from-cache <dir>` uploads the newest cached frame). Sub-stage it
like Stage 4 — pure logic first, dispatch+packaging last:
- **6a — new upload fn that reuses the artifact, does NOT re-capture/re-embed.**
  The cached file is already a complete v2 artifact (raw bytes + embedded EXIF).
  `upload.cache_upload(path, plugin=None)`: recover capture-ts from the v2 NAME
  (`parse_v2_name` — authoritative for ts; the name can't reliably split
  hyphenated vsn/camera), read the embedded meta back (`read_back_fields`) for the
  rest, and upload a **COPY** in a temp dir (upload_file may consume the source;
  the cached original must never be moved/mutated/evicted). CRITICAL: the RECORD
  timestamp = the ORIGINAL capture ts (`upload_file(timestamp=capture_ts)`), NEVER
  re-stamped to now; `meta.upload_timestamp` = real send time; tag
  `meta.source=from-cache`. Emit `plugin.duration.upload` only (no grab/embed
  phases in a from-cache run). Unit-test with a fake plugin + real embedded tmp
  jpegs: preserves capture-ts, faithful meta, cache untouched (file count+bytes
  unchanged), fail-soft on read/upload error, rejects non-v2 names.
- **6b — dispatch + exit-code mapping.** `_one_shot_from_cache(args)`: resolve the
  STREAM dir, select newest via `cache.scan_ring` (REUSE it so "valid v2 file" is
  defined in ONE place; ignores `.tmp`/non-v2), map outcomes — fail-fast
  EXIT_CONFIG_ERROR on missing dir OR empty cache (a scheduled uploader against an
  empty cache is a real misconfig worth surfacing, not a silent no-op), runtime
  upload failure -> EXIT_CAPTURE_ERROR. Wire into `main()`.
- **6c — ship the turnkey job PAIR.** `jobs/producer-continuous.yaml` +
  `jobs/uploader-from-cache.yaml` + `jobs/README.md` documenting the composed
  periodic-snapshot pattern. `--from-cache` points at the producer's STREAM dir
  (`<cache-root>/<cache-name>/<camera>/`); the two jobs must agree on
  root+name+stream. Producer reads creds from env/Secret (envFrom: secretRef),
  NEVER argv (the existing yolo/bioclip jobs embed the password in a
  `--snapshot-url` query param — Infra #10; don't copy that). Uploader needs NO
  creds (never hits the camera). Model the SES YAML on a real sibling job
  (`sage-yolo/jobs/*-oneshot.yaml`): `plugins[].pluginSpec.{image,args,selector}`,
  `nodes: {H00F: true}`, `scienceRules: cronjob(...)`, `successcriteria`.
- **6d — on-node**: see `references/on-node-verification-recipe.md`.

### Self-exit bounds as their OWN stage (`--max-count` / `--max-runtime`)
The "self-exit" that the spine lumps into Stage 6 is cleaner as its own small
stage (image-sampler2 Stage 3.3, built after Stage 6). Lets a `--continuous`
producer run as a bounded scheduler BURST (cron fires it, it captures a window,
exits, frees the slot) instead of a forever-daemon — fleet parity with the yolo
`--continuous Y --max-runtime 600` cron pattern. Technique:
- `--max-count N` = exit after N CAPTURES (heartbeats/wake-iterations do NOT count).
  `--max-runtime S` = exit after S wall seconds. Both default 0 = UNBOUNDED (forever
  behavior preserved exactly). Continuous-only, non-negative ints (negative →
  fail-fast). Bounded self-exit is SUCCESS (exit 0), not an error.
- **Check at the loop TAIL** (after the capture block, before the next sleep) so
  exit lands on a COMPLETED-CAPTURE edge, never mid-interval. Gate the runtime check
  on `captures >= 1` so a sub-interval `--max-runtime` still delivers the startup
  frame. Loop RETURNS normally so the caller's `finally` (Plugin teardown) runs.
- In the dual-grid loop add `max_runtime_ns` (wall-clock bound); map production
  `--max-count` onto the SAME capture counter the test harness uses
  (`max_captures`) but keep the test injection (`max_ticks`) and the production
  `--max-count` SEPARATE — effective bound = whichever is set (tests never set
  `--max-count`, production never sets `max_ticks`).
- For a pure-CPU plugin this is scheduler COMPOSABILITY + fleet parity, not resource
  contention (no GPU to free) — useful but lower urgency; fully unit-testable with
  the FakeClock, plus a real-clock smoke test (`--max-count 3` → exactly 3 frames →
  exit 0 in ~2s) proving the production path returns on its own.

### PITFALL: a new module needs a Dockerfile COPY line, or ImportError on-node
Every stage that adds a NEW top-level module (e.g. `heartbeat.py` in Stage 5,
`cache.py` in Stage 4) MUST also add it to the Dockerfile `COPY app.py acquire.py
... requirements.txt /app/` line. The full test suite passes locally (the module
is on the path) and the local build even succeeds, but the ON-NODE pod
`ImportError`s at runtime because the file was never copied into the image. This
bit twice in one session (heartbeat.py for Stage 5, verifying the COPY for
Stage 6). Make "did I add any new .py this stage? → is it in the Dockerfile COPY?"
a checklist item before the on-node build. There is no import-completeness test
that catches this off-node.

### Resolving an OPEN item by reading a watcher's SOURCE (not probing prod)
When a design decision hinges on "what does system daemon X actually do?" (e.g.
"will the upload-agent grab files I put here?"), read the daemon's SOURCE rather
than experimenting on the production node. `wes-upload-agent` is a bash rsync loop
(`main.sh` + `common.sh`); its `find_uploads_in_cwd()` is the exact scan predicate
(see `local-cache-ring-buffer.md` for the resolved contract). Grab it from raw
GitHub — `curl -s https://raw.githubusercontent.com/waggle-sensor/<repo>/main/<f>`
or list the tree via the GitHub trees API. HAZARD: `kubectl exec` into a live
system pod to inspect its config can DUMP secrets — exec-ing the upload-agent
prints its private SSH push key to the mounted config; do NOT record or reuse it.
Source-reading is both safer and more definitive than a one-off probe.

## Design principles Pete favors (recurring across decisions)
- Fail-FAST on bad input/config (clear error + nonzero exit); fail-SOFT at runtime
  (a bad frame/transient error warns + skips, never kills a long-running loop).
- Composable building blocks over do-everything flags: prefer two single-purpose
  invocations (e.g. producer + a `--from-cache` uploader) to one mode that both
  uploads AND persists. Resist feature-creep that re-couples concerns.
- The CLI surface is EXACTLY the locked design's destinations — no more. Do NOT
  add a flag to the shipped CLI just to have somewhere to inspect a stage's output
  before the real sink exists. (Real incident: mid-build I added `--out-dir` /
  `--out-path` to app.py so Stages 1/2 had a place to drop bytes before the upload
  path was written. Pete caught it: `--out-dir` re-used the exact name the design
  RENAMED to `--cache-dir` — confusing for anyone who knew the old tool — and
  `--one-shot` is upload-only, so a local one-shot sink contradicted the mode
  contract. Both were removed.) The lesson: a stage's deliverable is its LOGIC
  (verified by a throwaway script), not a user-facing convenience flag. Verify a
  pre-sink stage the same way you verify a spike — a `spikes/verify_<stage>.py`
  that imports the real modules and prints pass/fail CHECKS on a realistic (ideally
  on-node) input — then keep it in `spikes/` as reproducible evidence. When you
  catch yourself reaching for a scaffold flag, that's the signal to write a script
  instead. Add a regression test asserting the disallowed flags are absent
  (`--help`/parser option-strings) so they can't creep back.
- Verify in the DATA/HOST plane before declaring done ("Running" is not proof;
  confirm the actual pod/records/mount/permissions).
- Preserve old CLI arg semantics unless a break is deliberate and documented
  loudly (e.g. a `v2` filename marker when a prefix's MEANING changes).
- Heartbeat/liveness is PER-MODE, never blindly "every cycle." A fast producer
  loop (e.g. `--continuous` at up to 1 Hz) must NOT emit a liveness event per
  capture — it floods the data plane. Instead publish a PERIODIC summary
  (~once/min, its own configurable `--heartbeat-secs` decoupled from the sample
  interval) carrying cheap already-computed stats (e.g. cache image count + bytes),
  firing even when captures are skipped/failed (that's the "running but silent"
  case it exists to reveal). `plugin.duration.*` (ns, per fleet convention) fits a
  discrete-run mode (`--one-shot`) but does NOT apply to a continuous producer with
  no discrete run — the periodic summary replaces it as the liveness+progress signal.
- A capture/output "name+timestamp" convention should be a CAPTURE-TIME property of
  the artifact, applied identically on every path (local cache write AND upload),
  not something added only at upload. Watch for upload-centric doc framing (e.g.
  "pywaggle owns the {ts}- prefix") that leaves the local/cache-file naming
  implicit — state that the producer builds the full name itself for the cache and
  feeds the same capture timestamp to the uploader so the results are identical.

## Device credentials: env-only, never guess (HARD RULE — learned the hard way)
Camera/device secrets for a Sage plugin must be handled as follows. This came out
of a real incident where a fabricated password was fired at a lockout-protected
camera — do NOT repeat it.
- Credentials are ENVIRONMENT-ONLY (`CAMERA_USER` / `CAMERA_PASSWORD`), NEVER CLI
  flags — flags land in `ps`/argv, shell history, and logs. The plugin reads them
  from the env; the address (host/port/channel) may be flags with env fallbacks.
- On-node testing: pass the secret via STDIN, not the command line. Pattern:
  `printf '%s' "$PW" | ssh node '... read -r CAMERA_PASSWORD; export CAMERA_PASSWORD; ...'`
  — keeps it out of the remote argv and the node's history.
- REDACT secrets in every log line. If the code logs a request URL that carries
  `&password=`, scrub it to `password=***` before logging (rebuild the query
  string manually — `urlencode` will re-escape a `***` placeholder into `%2A%2A%2A`).
- NEVER fabricate/guess a credential. If you don't have it, STOP and ask, or source
  it from a node-side secret. Reolink (and many cameras) have a `remain_times`
  lockout: a wrong login returns `rspCode:-7 "login failed"` and DECREMENTS a
  counter toward locking the account. A guess is not a free probe — it burns a
  lockout attempt. Not-having-a-secret is a blocker to report, not a gap to fill
  with a plausible-looking string.
- The plugin should verify the fetched bytes are a real JPEG (SOI `ffd8` / EOI
  `ffd9`) and REJECT a non-JPEG body — a Reolink auth failure returns a small JSON
  error blob, not an image; saving it would silently poison the pipeline.

## Stage 1 acquisition module shape (native-still fetch, verified)
Factor acquisition into its own importable, mock-testable module (`acquire.py`):
- `build_<vendor>_snap_url(host, port, user, password, channel)` — query-param auth
  for Reolink; do NOT %-encode password-legal punctuation (see the reolink ref);
  add a random `rs=` cache-buster.
- `fetch_raw_still(url, timeout_s)` — bounded hard timeout; returns RAW bytes
  UNTOUCHED (no decode); validates SOI/EOI and rejects non-JPEG; maps socket
  timeout -> a `CaptureTimeout` and other failures -> a `CaptureError` (distinct
  types so callers can fail-fast one-shot / fail-soft continuous).
- `save_bytes_atomic(data, path)` — temp -> `os.write` -> `os.fsync` ->
  `os.replace`; clean up the `.tmp` on any failure so no torn/partial file is ever
  visible (this is also the groundwork the ring-cache atomic write reuses).
- Unit-test with `unittest.mock` patching `urllib.request.urlopen` — no real
  camera/network. Then ONE real on-node capture to confirm (valid JPEG, right
  dimensions, no `.tmp` litter, timeout path clean). Keep live camera hits minimal
  (lockout risk above).
