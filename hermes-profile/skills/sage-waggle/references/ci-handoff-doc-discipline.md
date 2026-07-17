# CI-handoff doc discipline for WES prototype repos

When a prototype WES/Sage repo (e.g. wes-nodeinfo-injection, wes-local-cache-manager,
pywaggle2 changes) is being handed to the Sage CI team, the deliverable is a clean,
CURRENT, succinct doc set — not an exploration log. Pete asks for this explicitly as a
final pass per repo, and runs a real pre-prod review after ("anything else to
clean/double-check?") expecting genuine scrutiny.

## The three linked pieces (work them one at a time, then integrate)
1. **wes-nodeinfo-injection** — WES change: 5 `WAGGLE_NODE_*` env vars to every plugin
   pod via `wes-identity` ConfigMap + scheduler `envFrom`. Tagged v1.0.0.
2. **wes-local-cache-manager** — DaemonSet capping the shared `/local-cache`. Tagged
   v0.1.2 (v0.1.1 = cache-unit convention fix; v0.1.2 = harvested mount mechanics +
   eviction-limitation note from `local-cache-design.md` into HANDOFF).
3. **pywaggle2-nodeinfo** (own repo, tagged v0.1.0) — the reader side
   (`get_node_info()`, consumes the injected env; production namespace `waggle/data/`).
   CANONICAL source of `node_info_env.py` now lives here; `wes-nodeinfo-injection`
   keeps a byte-identical MIRROR under `pywaggle2/` only for its own `test_e2e.py`.
Consumer that ties #1+#2 together: image-sampler2 (`nodemeta._runtime_identity` reads
the env; `cache.py` writes `/local-cache`). Do each repo's review before integrated
testing.

## The doc-pass checklist (what Pete wants each doc to cover, succinctly)
- WHAT is currently deployed / how it works (not what paths were explored to get there)
- HOW to run setup AND teardown to test
- RISKS for fleet-wide deployment (a table works well)
- HOW to fold it into base CI (numbered, mechanical steps)
Cut: dated gate-by-gate narratives, historical bug stories, "pending/next gate"
language, design-doc section refs the CI team won't have (`§2.4.3`), path/exploration
history, "154 restarts"-style transient incident detail.

## CORRECTNESS-CHECK docs against the ACTUAL code, not against memory
The highest-value find this class of pass produces is doc/convention DRIFT — docs that
describe an intended contract the code never actually implemented. Method:
- grep the real consumer for how it ACTUALLY uses the thing, then reconcile the doc to
  reality (prefer fixing DOCS over changing a stable consumer right before integration).
- Verify every load-bearing claim: test COUNTS ("12 tests" when `make test` shows 21),
  byte values vs their GiB/GB comments, image tags/versions, patch line-targets vs the
  real function, cross-file references (`booltoPtr` reused not redefined, k8s pin).
- Real example (wes-local-cache-manager v0.1.1): docs said a cache "unit" is
  `<namespace>/<plugin>` and told plugin devs to mount `-v .../local-cache/<ns>/<plugin>:/local-cache`.
  But the manager only caps whatever sits at `CACHE_UNIT_DEPTH` (default 2) below the
  root — it does NOT enforce naming — and the real consumer (image-sampler2) writes
  `<cache-name>/<camera>` and mounts the cache ROOT. The old mount example
  double-nested the path. Fix: describe the unit generically ("any depth-2 dir, e.g.
  `<cache-name>/<camera>`"), mount the ROOT. Also dropped a stale `--require-local-cache`
  flag reference (flag was removed; cache now required unconditionally).

## Cross-piece contract to keep in lock-step
The env-reader sentinel contract MUST match between `pywaggle2/node_info_env.py`
(`read_node_info`) and image-sampler2 `nodemeta._runtime_identity`: VSN sentinels
`("","0")→None`; coords by RANGE `|lat|>90`/`|lon|>180`→None (catches the `999`
sentinel); node_id `""`→None; mobility missing/""→"unknown". If you touch one, verify
the other still mirrors it — and update the HANDOFF's "keep aligned" note.

## Versioning a docs-only release
Docs-only correctness pass with no image rebuild → bump the repo/VERSION + CHANGELOG
(e.g. 0.1.0→0.1.1) but keep the manifest image tag at the last CODE release, and add a
one-line manifest comment saying why the image tag trails the repo version.

## Multi-doc k8s YAML lint false-positive
The write/patch linter flags multi-document k8s manifests ("expected a single document
in the stream" at the `---` separator). This is a FALSE POSITIVE — verify with
`python3 -c "import yaml; list(yaml.safe_load_all(open(f)))"` and move on.

## Promoting a stray code file into a standalone handoff repo
When a deliverable piece is just a loose file buried inside a DIFFERENT repo (e.g.
`node_info_env.py` living in `wes-nodeinfo-injection/pywaggle2/` for that repo's e2e
test, plus a loose design doc in `~/AI-projects/`), package it as its own repo so CI
gets one self-contained handoff. Pattern that worked (pywaggle2-nodeinfo v0.1.0):
- **Scope tight** — node-info-only, NOT the whole library redesign. Don't bundle
  "ready" work with still-draft RFC sections; ship what's actionable.
- **Mirror the UPSTREAM production layout** so landing it is a straight copy —
  `waggle/data/node_info_env.py` (+ empty `__init__.py` at each package level), not a
  flat file. HANDOFF then says "drop into `waggle/data/` behind `Plugin.get_node_info()`".
- **Give it its OWN tests.** A file exercised only indirectly by another repo's e2e
  has no standalone coverage — write real unit tests (`tests/test_*.py`, pure-dict
  in / value-object out is easiest since the reader takes an `env=` param). Match the
  sibling repos' harness: self-bootstrapping-venv Makefile (`make test`), VERSION,
  CHANGELOG, `.gitignore`, git author = same as the other CI repos
  (`Pete Beckman <flint-pete@users.noreply.github.com>` — grep a sibling repo's last
  commit to match).
- **Standard doc trio**: README (what+how-to-test), DESIGN (the WHY — extract just the
  relevant slice of the big RFC, not the whole thing), HANDOFF (wire contract,
  verification, numbered "what CI owns").
- **Canonical-vs-mirror discipline.** After moving, the new repo is CANONICAL; leave
  the old copy as a byte-identical mirror where a test needs it, and update the OLD
  repo's HANDOFF to say "canonical now lives in <new-repo>; this is a mirror — keep
  byte-identical." Name ALL consumers that must stay in lock-step (here: the mirror,
  pywaggle2-nodeinfo, image-sampler2 `nodemeta`). `diff -q` to prove identity.
- A tag-after-a-post-tag-doc-commit shows as `vX.Y.Z-N-g<sha>` (e.g. v1.0.0-1-g…);
  fine for a doc-only sync commit — the release tag still points at the real state.

## Verification-gate re-fires on already-committed files (don't loop)
A post-turn system gate can flag the SAME files as "unverified" for several turns
even after you committed them and ran the suite green — it keys off the turn's
cumulative changed-set, not on whether there's uncommitted drift. When you made NO
edits this turn, do NOT re-run identical tests in a loop. Instead prove it's settled:
`git status --porcelain` (empty = clean) and `git diff --quiet HEAD -- <file> && echo
identical` for each flagged path. Report "no drift, last run green, settled" and stop.
Re-running `make test` on byte-identical files proves nothing new and wastes turns.

## Harvesting a loose companion design doc into the deliverable repo
A deliverable repo often has a loose, uncommitted companion RFC in `~/AI-projects/`
(e.g. `local-cache-design.md` beside `wes-local-cache-manager`). Before calling the
repo done, ask "anything useful to harvest?" Method: grep the repo's existing docs for
each candidate topic from the loose doc to isolate NET-NEW material vs already-covered
(copying covered content just creates drift). The highest-value harvest is usually the
"how does a plugin actually WIRE this up" mechanics the deliverable docs omit — e.g.
for local-cache: the `volume:` hostPath field ALREADY exists in `PluginSpec`
(`Volume map[string]string`, SES mounts each `from→to`), its caveats (requires a
nodeSelector; unresolved commented-out `IsOwnedByRoot` root-ownership TODO), and the
clean auto-mount opt-in steer (`sage.yaml local_cache: true` → SES auto-mounts the
WES-owned path, sidestepping the root-owner concern). Put harvested CI-facing material
in HANDOFF; leave design rationale in the doc where it lives; confirm scope with Pete
before wholesale copying (he leaned "harvest all: mount mechanics + eviction-ordering
limitation note"). Note also the node-cap eviction nuance worth flagging as a known
limitation: the sweeper evicts oldest-first GLOBALLY on the node pass, whereas a
node-cap breach arguably should evict proportionally from the biggest over-cap units.

## Duplicate-edit hazard when patching docs across interrupted turns
Interruptions (empty-response retries, out-of-band messages) can cause markdown
patches to LAND TWICE or collide, producing duplicate CHANGELOG version headers and
duplicate `## sections`. Before committing a doc-heavy change, VERIFY structure, don't
assume: `grep -nE "^## \[" CHANGELOG.md` (each version header exactly once) and
`grep -nE "^## " HANDOFF.md` (no repeated section titles). If a section looks
"already there," it may be your own earlier edit this turn — reconcile against the
committed baseline with `git diff HEAD -- <file>` to see what you ACTUALLY changed vs
what was already committed, then dedupe to a single clean copy. Make the CHANGELOG
entry list ALL the changes the diff shows, not just the first one you remember.

## Relocating loose docs into a design-doc repo (chase-and-fix references)
When the loose `~/AI-projects/` design/planning docs need a home (Pete asked for a
`sage-design-planning` repo holding the RFC + issue lists + status), the hazard is
BROKEN REFERENCES after the move. Method that worked:
- **Build the complete edit map FIRST**: `grep -rln <docbase>` for every moved doc, then
  EXCLUDE the frozen `sage-hermes-brain/` (never edit — it keeps its own snapshots) and
  `tmux-logs/` (historical). What's left is what you must fix.
- **Grep ALL file types, not just `*.md`.** References hide in `.sh` (script header
  comments like `gen-wes-identity.sh`), `.py` docstrings, `.txt`. A `--include="*.md"`
  sweep will MISS them and leave danglers the post-turn scan then catches — do the
  all-extensions pass up front.
- **Mutual refs among the moved docs**: if they all move together into one dir, bare-
  filename refs (`Infra-problems-to-fix.md`) still resolve; but ABSOLUTE refs
  (`~/AI-projects/<name>.md`) between them now point at the empty old path — convert
  those to bare filenames (resolve in-dir regardless of repo location).
- **External refs** (plugin repos, both `node_info_env.py` copies, the big map): rewrite
  `~/AI-projects/<name>.md` → `~/AI-projects/sage-design-planning/<name>.md`.
- **Repoint refs to ALREADY-DELETED docs too** (e.g. lingering `local-cache-design.md`
  pointers) → the repo that absorbed them (`wes-local-cache-manager` DESIGN/HANDOFF).
- If you touch a script/`.py` that a test exercises, re-run `make test` even for a
  comment-only edit, then commit. Final: all-extensions `grep -rnE "~/AI-projects/(…)"`
  excluding brain/tmux/venv must return NOTHING. Pete chose "chase-and-fix all" over
  redirect-stubs — offer both, but stubs are the fallback if refs are too scattered.

## Mapping intertwined pieces into a big-picture feature map
Pete periodically wants the whole system mapped: how N intertwined pieces are SUPPOSED
to relate, what's built/verified vs designed-only, what each waits on. Produce a durable
`SAGE-STACK-MAP.md` (loose file is fine). Do it RIGHT:
- **Verify ground truth per piece — do NOT trust memory or a prior summary.** grep each
  repo for what it ACTUALLY does: does a plugin READ `/local-cache` or open its own
  camera? does it call `get_node_info()` or read `WAGGLE_NODE_*` env ad-hoc? This is
  where surprises live (e.g. yolo/bioclip capture their own frames — the producer/
  consumer wiring is DESIGN-ONLY, not built; birdnet already reads
  `WAGGLE_NODE_GPS_LAT/LON` ad-hoc so it's furthest along on node-info).
- **Do not omit pieces.** Pete will notice a missing plugin (birdnet — an AUDIO plugin,
  distinct from the image plugins). Enumerate the full set before writing.
- **Umbrella-naming a feature set**: Pete may define a name to mean a GROUP (he defined
  "pywaggle2" = wes-nodeinfo-injection + wes-local-cache-manager + pywaggle2-nodeinfo
  together = the platform features that ENABLE image-sampler2). Lead the map with a
  "what this name means here" table so the naming is unambiguous.
- **Distinguish deploy-NOW-standalone from enables-new-features.** Standalone plugins
  (yolo/bioclip/birdnet) run TODAY on a stock node without the new tooling; they can be
  deployed for testing even though core WES doesn't support the new features yet. Say so
  explicitly — "deployable now" vs "waiting on the mount" are different states.
- Columns/sections Pete asked for: short feature summary · where it goes (WES component
  vs user plugin) · what's needed to use it locally/on-Thor · what's needed to hand to
  CI. Use legend markers (✅ built+verified / 🟡 partial / 🔴 design-only / ⬛ CI-owned).

## Doc cruft can RE-CREEP after a code fix — verify code, then purge narrative docs
A fix in code (image-sampler2 removed the silent `/tmp` cache fallback → fail-fast at
v0.5.1, confirmed in `cache.py` `resolve_cache_root` = `explicit > $IS2_CACHE_ROOT >
/local-cache`, no `/tmp`) does NOT automatically fix the PROSE docs. Stale wording
lingered in `readiness-gap.txt` (BLOCKER 1 still described the old fallback as current)
and even re-entered a fresh map by echoing that stale text. When the user says "I
thought we removed X but it's back": (1) confirm the CODE is actually correct (grep the
resolver), (2) then it's a DOC purge — update the narrative/blocker docs to describe the
fail-fast reality, not the removed behavior. Historical framing ("NO /tmp fallback since
v0.5.1; removed because it produced frames no consumer could read") is fine; present-
tense "lands on /tmp" is the bug.

## Pushing CI repos to GitHub — SCAN FOR SECRETS FIRST (public repos)
The Sage prototype repos are pushed PUBLIC to the `flint-pete` GitHub account
(`gh auth status` confirms; match the visibility of an existing sibling with
`gh repo view flint-pete/<repo> --json visibility`). Before `gh repo create … --public`,
scan for secrets/PII — Pete's rules are strict (private email `pete.beckman@northwestern.edu`,
his phone, ANL email must NEVER hit a public repo).
- **Scan TRACKED files only, not the working tree.** The real hazard is a repo that
  vendors upstream clones: `wes-nodeinfo-injection` has a `.upstream/` dir with full
  waggle-edge-stack + edge-scheduler clones containing a REAL private key
  (`ansible/test-keys/key.pem`), a chirpstack `secret=…`, and k8s service-account
  tokens. A naive `grep -r` over the dir screams danger — but `.upstream/` is
  GITIGNORED and untracked (0 tracked files), so none of it ships. Confirm with
  `git ls-files .upstream/ | wc -l` (== 0) and `git show HEAD:.gitignore`.
- Correct scan = tracked-only: `git ls-files -z | xargs -0 grep -nHiE
  "<PRIVATE_EMAIL_DOMAIN>|ghp_[A-Za-z0-9]{20}|-----BEGIN.*PRIVATE KEY|<OWNER_PHONE_PREFIX>[0-9]+"`.
- Design-language false positives are fine: `sage-design-planning` says "password"/
  "token" dozens of times but only as credential-handling DESIGN prose (e.g. "read
  creds from `CAMERA_PASSWORD` env, never argv") — no actual secrets. Tracked node
  manifests carry real GPS but that's PUBLIC node metadata, not a secret.
- Create+push: `gh repo create flint-pete/<name> --public --source=. --remote=origin
  --description "…" --push`, then `git push origin --tags` (repo-create --push does NOT
  push tags). For repos that already have a remote, just `git push origin <branch>` +
  `git push origin --tags` (unpushed tags are easy to forget — e.g. wes-local-cache-
  manager had v0.1.1/v0.1.2 unpushed). Verify each: local HEAD == `origin/<branch>`
  and `git tag` list matches. Default branch may be `master` (gh-created) or `main`
  (older repos) — read `git branch --show-current`, don't assume.
- These live under `flint-pete` by convention (matches existing repos); if a piece is
  meant to become the upstream deliverable it later moves to `waggle-sensor/` org —
  that's the CI team's merge, not ours. Note it, don't presume.

## "What's ACTUALLY in the current code?" scope-check
Pete periodically asks what a feature/umbrella's code REALLY implements (vs the design
doc's ambitions) — e.g. "is there anything else in pywaggle2's current code besides
node-info + the cache?" Answer from the CODE, not the RFC:
- List the tracked deliverable of each piece: `git ls-files | grep -vE
  '^\.upstream/|test|fixtures'` — patches + gen script + reader + sweeper, nothing else.
- Enumerate the real API surface: `grep -nE "^def |^class |^[A-Z_]+ ="` on each logic
  file (reader = `read_node_info` + `NodeInfo` 6-field tuple + 2 clean helpers; sweeper
  = eviction/validate/sweep only, NO producer/consumer API); `grep -oE
  "WAGGLE_NODE_[A-Z_]+"` the gen script for the exact injected payload (5 vars).
- Name what is DESIGN-ONLY / not-in-the-code so the boundary is explicit: the Layer-1
  cache PRIMITIVE (`cache_file()`/`read_cache()`) lives only in `image-sampler2/cache.py`,
  NOT hoisted into pywaggle2; live-GPS Tier-2, the acquisition ladder, cred handling,
  geo-filtering are RFC §1/§3 only. Key nuance to state: the cache MANAGER
  (wes-local-cache-manager) is the platform Layer-2 quota backstop, NOT the read/write
  library — so "pywaggle2 as the library plugins call" is still MISSING the cache
  primitive even though a cache exists.

## Assembling ecr-meta/ for a NEW plugin from a sibling/v1 (VERIFIED sage-bioclip2 2026-07-15)
A Sage plugin needs an `ecr-meta/` dir (the ECR catalog metadata) for portal
submission — 7 files. A new plugin (esp. a re-architected v2) should ADAPT a
sibling's set, not author from scratch. The 7 files (see any repo's
`ecr-meta/README`, itself a copyable format guide):
- `ecr-science-description.md` — 1-page science. Do NOT copy a v1's verbatim: REFRAME
  it around the NEW architecture. For a v2 cache-consumer, lead with the
  cache-consumer + detect→classify cascade story and the `--input` full-frame-vs-crop
  switch, keep the model/science paragraphs, drop v1's camera-source specifics. Keep
  the "published data" + "reporting-vs-saving" sections a downstream consumer needs.
- `ecr-project-keywords.txt` — start from the v1 model keywords, ADD the architecture
  terms (Cache Consumer, Producer-Consumer, Detect-Classify Cascade, pywaggle2,
  Frame-anchored) — same broadening as the ECR science-description keywords for yolo2.
- `ecr-project-url.txt` → the NEW repo URL. `ecr-credits-license.txt` → copy verbatim
  (authors/collaborators/funding NSF 2436842/BSD-3 are constant across the family).
- `ecr-icon.jpg` (512x512) + `ecr-science-image.jpg` (≥1920x1080) — REQUIRED before a
  real ECR submission. Copy the v1 model plugin's as appropriate starting art (a
  species classifier reuses bioclip's; swap for cascade-specific art before formal
  submit). They're binary — confirm `.gitignore` does NOT exclude `*.jpg` so they
  commit (`git check-ignore ecr-meta/*.jpg` must return nothing).
- `README` — the format guide; copy a sibling's verbatim (identical across repos).
Note: `name`/`version`/`description` come from sage.yaml, NOT ecr-meta/. ecr-meta is
only needed for the SES/ECR-catalog path; a `pluginctl run` side-load ignores it — so
you can deploy+verify live BEFORE ecr-meta exists, then backfill it for submission.

## Tag the deliverable
After the doc pass + green suite, commit and `git tag -a vX.Y.Z -m "…"` with a summary
of what the release contains + verification status. That's the handoff artifact.
(A loose design doc NOT in a git repo — e.g. `~/AI-projects/pywaggle2-design.md` — has
nothing to commit/tag; just save in place. Its CODE half lives+tags elsewhere.)

## Cleaning a long-form DESIGN DOC / RFC (distinct from a deliverable repo)
When the "piece" is a design doc rather than a code repo (e.g. pywaggle2 = a 945-line
RFC + the `node_info_env.py` reader), the cleanup is different from a repo doc pass:
- **First separate code from doc.** The end-to-end CHECK is on the code (run its tests
  — here the reader's 7 e2e are green in wes-nodeinfo-injection's `make test`); the
  cleanup is on the prose. Don't conflate them.
- **Reframe SHIPPED sections from "proposed" → "implemented".** If a design section
  described future work that has since been built (e.g. §2.3 "Requires a WES side" →
  now `wes-nodeinfo-injection v1.0.0`), lead it with a dated `> STATUS: built and
  verified …` blockquote and shift to past tense. Then reconcile downstream sections
  that still say "get X agreed before the API freezes" so they don't CONTRADICT the new
  STATUS (a minimal surgical touch, not a rewrite, if the user scoped you to specific
  sections).
- **Distill dated exploration logs to the FINDING.** A section full of
  `2026-07-08 23:41 UTC`, ssh/`ip neigh` discovery narrative, device/CPU inventory, and
  per-node coord dumps → cut to what a reader needs: the confirmed result + why it
  matters (e.g. "live jittering gpsd confirmed on a static pole node; jitter is
  receiver noise not motion; unsurveyed-manifest = the None edge case"). Keep the
  testable-now-vs-still-blocked distinction.
- **KEEP device/technical detail that JUSTIFIES a design choice.** Not all specifics are
  cruft: "gpsd holds `/dev/ttyACM0` exclusively (u-blox 7) → a plugin can't read the
  device, must go through the socket → therefore a library wrapper is correct" is a
  design argument, not an exploration timestamp. Cut the log, keep the rationale.
- **Confirm scope with the user before sweeping cuts to an authored RFC.** These docs
  are Pete's; he'll say how aggressive (he scoped this pass to "clean up A and B" —
  reframe-as-implemented + distill-the-log — and to leave the status/next-step section
  alone). Offer the cruft categories, get the call, then execute exactly that scope.
- **Trimming a SHIPPED section that now duplicates a repo's DESIGN.md (§2-stub move).**
  When a section's content has moved into a standalone repo (pywaggle2-design.md §2 →
  pywaggle2-nodeinfo/DESIGN.md), don't delete it and don't leave the dual-copy. Replace
  the ~560 lines with a concise STUB: a `> This section has shipped and moved` blockquote
  pointing at the repo's DESIGN.md + HANDOFF, a 1-paragraph problem/API/status recap
  (enough that other sections' cross-refs still make sense), and a "do NOT edit here —
  edit in the repo" note. Preserve the original detail inside a collapsed
  `<details><summary>…superseded, kept for history</summary> … </details>` fold so
  intra-section cross-refs (§2.2.1, §2.3) still resolve and history isn't lost. VERIFY
  the fold is balanced: `grep -c "<details>"` == `grep -c "</details>"` == 1. Then
  reframe the doc's Status/next-step section so it stops treating the shipped section as
  pending. Result: rendered length drops sharply (922 → ~386 visible) while nothing is
  destroyed. Is-NOT-a-duplicate test: a companion RFC is only a delete/harvest candidate
  when it's ~90% redundant with its repo (local-cache-design.md was); a doc that also
  holds still-unbuilt scope (pywaggle2-design.md §1/§3) STAYS as the roadmap — only trim
  the shipped slice.
