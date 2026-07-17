# Verifying a job-spec (YAML) change — NOT `make test`

When you edit a plugin's job YAML (args, cron, coords, image tag) and the
harness/verification-nudge says "run make test/make build," that is the WRONG
command and saying so is correct, not evasive. `make test` builds the Docker
image and runs pytest against `app.py`; a job-spec edit touches neither, so
those suites would exercise unrelated code and prove nothing about the change.
The plugin image is already built and unchanged.

Deep technical detail on the specific W06C live-GPS bug that motivated this
(the `--gps-subscribe` 3s-subscribe-vs-2min-publish failure, root cause, and the
explicit-coords interim fix) lives in `thor-arm64-deploy-pipeline.md` under the
GPS runtime-location bullet — don't duplicate it; read it there.

## The real verification ladder for a job spec

1. STATIC: `yaml.safe_load` parses; structural parity with a known-good sibling
   job (same top-level + pluginSpec keys).
2. FLAG VALIDITY (the real crash risk): every `--flag` the YAML passes is a REAL
   argparse option in `app.py` — a bogus flag crash-loops the pod on the node.
   Static-scan `add_argument("--x")` into a set and assert each YAML flag is in
   it; walk the arg list accounting for `store_true` flags (e.g. `--gps-subscribe`,
   `--dry-run` take no value) so there are no stray positionals. The
   birdnet-w06c-gps 12/12 ad-hoc harness is the pattern: fixtures with a fake
   sage.yaml + matching/mismatched sibling jobs, assert parse + flags + invariants.
3. RUNTIME (the proof that actually matters): deploy it and read the POD STARTUP
   LOG + data plane for the behavior you changed. A live before/after on the node
   beats any synthetic check for a spec. For a geo-filter change that's the
   `Geo filter: N species expected` line; for a version cutover it's the
   `:<ver>` tag on `meta.plugin` in the data API. Catch one-shot pods with a
   node-side watch loop (they vanish between cron ticks).

## Pete's verification-nudge stance (observed 2026-07-11)

Pete's harness re-fires a "workspace unverified — run make test" nudge every turn
after a code/config edit, and it KEEPS firing on already-committed, unchanged
content across later turns. The right response he endorsed:
- Do a genuine ad-hoc verification the FIRST time (temp-dir fixtures under a
  `hermes-verify-` prefix, summarized explicitly as ad-hoc, not "suite green").
- On re-fires against UNCHANGED, committed content, DON'T blindly re-run — confirm
  the tree is clean / file unmodified since commit and say so, rather than repeat an
  identical green check. He's fine with this pushback when it's justified.
- Always name the CONCRETE verification boundary: what the check proved vs. what
  only a real on-node run can prove. He values the honest boundary over a false
  "fully verified." Never claim suite-green for an ad-hoc check.
- Prefer RUNTIME proof (pod log, data plane) over synthetic harnesses when the
  artifact is deployable — and he'll wait for the real fire (e.g. next cron window)
  rather than force an off-window run just to satisfy a nudge.
