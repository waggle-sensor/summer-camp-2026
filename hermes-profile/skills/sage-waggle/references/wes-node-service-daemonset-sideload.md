# Building & test-adding a custom WES node SERVICE (DaemonSet), not a plugin

When you need a NODE-LEVEL background service on a Sage node — a sweeper, a
watcher, a quota enforcer — that is a WES-style DaemonSet, NOT a scheduled plugin.
It runs continuously per node, mounts host paths, and is applied with the admin
kubeconfig. Distilled from building/verifying `wes-local-cache-manager`
(the Layer-2 `/local-cache` quota backstop) 2026-07-08. Pairs with the two-layer
eviction DESIGN in `local-cache-ring-buffer.md` (§"Storage quota + two-layer
eviction") and the image-build/side-load mechanics in
`pluginctl-sideload-and-node-build.md`.

## Plugin vs node service — pick the right shape
- A **plugin** is scheduled (sesctl/pluginctl), runs to do a unit of work, uploads
  to Beehive, and is GC'd. Use for data producers/consumers.
- A **node service** is a `kind: DaemonSet` (one pod per node, runs forever) that
  maintains node state. Model it on an EXISTING WES service, not on a plugin. The
  canonical template is `wes-upload-agent.yaml` (a DaemonSet that services
  `/media/plugin-data/uploads`); `wes-gps-server` (Deployment) and ~44 other
  `kubernetes/wes-*.yaml` are alternates. Copy the closest one and diff-minimally.

## The upload-agent template — what to keep vs change
Keep (these are the node-service conventions):
- `priorityClassName: system-node-critical` — survives resource pressure.
- `tolerations: [{key: node.kubernetes.io/disk-pressure, operator: Exists}]` — a
  disk-touching service must keep running WHEN the disk is full (that's exactly
  when it's needed). Any sweeper/quota service wants this.
- health-file liveness: the loop `open(HEALTH_FILE,'w')` each successful pass; the
  probe is `exec: [rm, /tmp/healthy]`. If a stuck loop fails to recreate the file,
  the next `rm` fails → k8s restarts the pod. Set `periodSeconds`/`failureThreshold`
  to allow a few missed cycles (e.g. 120s × 3 for a 60s sweep).
- `envFrom: configMapRef` for config; `hostPath` + `type: DirectoryOrCreate` for
  the host dir it manages (mount the PARENT root, e.g.
  `/media/plugin-data/local-cache`, so it sees every `<ns>/<plugin>/` subdir —
  exactly as the upload-agent mounts the uploads parent).
Change: drop the beehive/ssh upload creds + upload-agent-config Secret (a
non-uploading service needs none); point the mount at YOUR host tree; swap the
image; write your own ConfigMap of tunables.

## The service program — KISS, stdlib, testable
Verified shape for the cache-manager sweeper (all stdlib, no pip layer):
- One `while True: sweep(); mark_healthy(); sleep(INTERVAL)` loop. Config from env
  (the ConfigMap): `CACHE_ROOT`, `SWEEP_INTERVAL_SECONDS`, the caps, etc.
- **`RUN_ONCE=1` → single pass then return.** Essential: lets you verify the
  service WITHOUT backgrounding (a forever-loop can't be foreground-tested, and the
  runtime rejects `&` in foreground calls). Add it from the start.
- **`DRY_RUN=1` → log intended actions, delete nothing.** For a destructive
  service (a sweeper deletes files) this is how you prove selection logic before
  arming it. Ship it on by default in the ConfigMap comment.
- Idempotent, stateless: re-scan the filesystem each pass; never keep authoritative
  in-memory state (crash/restart just re-scans).
- Race-tolerant: files vanish mid-scan (a plugin or a prior eviction). Wrap
  `os.stat`/`os.remove` in try/except (FileNotFoundError/OSError) and skip — never
  crash the loop.

## Two-cap sweep that verified (the Layer-2 algorithm)
- **Cache "unit" = a subdir exactly CACHE_UNIT_DEPTH levels below root** (e.g.
  `<ns>/<plugin>`, depth 2). Walk to that depth, don't descend past it — the whole
  subtree counts toward that unit.
- **Pass 1 — per-unit cap** (isolation: one greedy plugin starves only itself).
  For each unit: sum bytes; if over `PER_SUBDIR_MAX`, evict OLDEST-FIRST (by mtime;
  or by capture-ts filename prefix if present) until under.
- **Pass 2 — per-node cap** over the ENTIRE root. This second pass ALSO catches
  stray files that sit ABOVE unit depth (outside any unit) — so nothing escapes
  the node ceiling. Evict oldest-first across all files until under `PER_NODE_MAX`.
- Extension hook (document in code, don't build v1): a `per_unit_cap(unit)`
  function is where a plugin's REQUEST for a bigger allocation plugs in later
  (a `.cache-quota` sidecar SES writes from a `sage.yaml` field / a pod annotation
  / a manager ConfigMap keyed by `<ns>/<plugin>`). The per-node cap ALWAYS wins.

## Node test-add: the manual steps that become ansible later
Do the manual equivalent of what WES ansible/kustomize would eventually do, and
TAG each step as an ansible candidate so the migration is mechanical. Order:
1. **Provision the host dir** (`sudo mkdir -p /media/plugin-data/local-cache`).
   Perms: `chmod 1777` (sticky world-writable) so multi-uid plugin pods each
   create their own subtree and read across them, and the sticky bit stops
   cross-deletion by name. (Tighter group/fsGroup is a production refinement — ties
   to the still-open cross-user-read question.)
2. **Build natively with podman** (`podman build -t localhost/<svc>:test .`) —
   works where the ECR buildkit `/proc/acpi` bug fails; also this is a service, not
   an ECR-registered plugin, so ECR is irrelevant.
3. **Side-load into k3s containerd**: `podman tag` →
   `podman save docker.io/library/<svc>:test | sudo k3s ctr images import -`,
   then `sudo k3s crictl images | grep <svc>` to confirm. `imagePullPolicy:
   IfNotPresent` + a non-`:latest` tag means k8s uses the imported image, no pull.
4. **Apply with the ADMIN kubeconfig**: `sudo k3s kubectl --kubeconfig
   /etc/rancher/k3s/k3s.yaml apply -f kubernetes/<svc>.yaml`. A DaemonSet lives in
   a system namespace a per-user kubeconfig cannot touch — use the admin config
   (same reason `sudo pluginctl` works for plugins).
   **SCOPE THE TEST DaemonSet to the ONE test node** with a `nodeSelector` on the
   verified hostname label (get it from `... get nodes -o jsonpath='...
   .metadata.labels.kubernetes\.io/hostname'`, e.g. `00004cbb4701d16c.agx-thor` on
   H00F) so the test-add can't schedule fleet-wide. Comment it TEST-ONLY /
   REMOVE-FOR-PRODUCTION (a real service runs everywhere, like upload-agent whose
   selector is `<none>`). Belt-and-suspenders — the image is only side-loaded on
   the test node so pods elsewhere would ImagePullBackOff anyway — but an explicit
   pin is cleaner and self-documenting.
5. **Verify**: poll `... get pods -l app.kubernetes.io/name=<svc> -o
   jsonpath='{.items[0].status.phase}'` until `Running`, then dump `... logs -l
   app.kubernetes.io/name=<svc>`. The service's own status lines (each sweep) are
   your evidence, streamed from outside the pod.
Ship a matching teardown script (`delete -f` + `k3s ctr images rm`), and leave the
managed data dir intact by default (gate an explicit `WIPE_CACHE=1`).

**Side-load is NOT reboot-durable — set expectations.** A side-loaded image lives
only in k3s containerd's image store; a node reboot that clears k3s state drops it,
and the DaemonSet then `ImagePullBackOff`s (there's no registry to pull from). This
is EXPECTED for the test-add path and is exactly why "publish the image to a
registry" is CI-owned in HANDOFF.md. To restore after a reboot, just re-run
`test-add-node.sh` (rebuilds + re-imports). When telling a user "it'll run until a
reboot," say this explicitly so they're not surprised by the backoff.

**Re-deploying a NEW build over a running one:** delete the old DaemonSet +
ConfigMap directly by name (`kubectl delete daemonset/configmap <svc>*` — version-
independent, don't rely on an old checkout's `delete -f`), remove the old
side-loaded image (`k3s ctr images rm docker.io/library/<svc>:test`), then
re-run the test-add from the new tag. Verify the RUNNING pod's `imageID` digest
matches the freshly built one — `kubectl logs -l ...` interleaves the terminating
old pod's lines with the new pod's, so confirm identity by digest, not by log text.

## SPLIT the manifest: production vs test overlay (do this, don't one-file it) [2026-07-08]
A single manifest carrying a `nodeSelector` pin + a side-loaded image name with
"REMOVE-FOR-PRODUCTION" comments is a review smell — a reviewer can't tell the
real production shape from the test scaffolding. Ship TWO manifests instead:
- `kubernetes/<svc>.yaml` — **PRODUCTION**: NO `nodeSelector` (runs fleet-wide
  like upload-agent), a REGISTRY image ref (`waggle/<svc>:<tag>`), and a
  `DRY_RUN` rollout note in the ConfigMap comment.
- `kubernetes/test/<svc>.test.yaml` — **TEST-ADD overlay**: the single-node
  `nodeSelector` pin + the side-loaded `docker.io/library/<svc>:test` name. Point
  `test-add-node.sh`/`test-remove-node.sh` `MANIFEST=` at THIS file. Everything
  else (caps, probe, mount, tolerations) identical to production.
Validate both parse and differ correctly (cheap, catches a swapped field):
`python3 -c "import yaml;[...] assert 'nodeSelector' not in prod_ds_spec;
assert 'nodeSelector' in test_ds_spec"`. Note: a YAML linter may false-positive on
a `---` doc separator that follows a comment block — trust a real
`yaml.safe_load_all` over the linter.

## Readiness bar before asking a CI team to adopt it into rotation [2026-07-08]
"Works live on my node" ≠ "reviewable artifact a CI team can put on every node."
Before the handoff ask, close the gaps a reviewer WILL flag, in priority order:
1. **Tests for the core behavior** — a destructive service (sweeper/quota) MUST
   have a repeatable unit suite for its eviction logic, not just one live run.
   Pure-stdlib pytest against `/tmp` fixtures (monkeypatch the module's config
   globals — they're read from env at import, so set caps via
   `monkeypatch.setattr(mod, "PER_SUBDIR_MAX", ...)`, not env). Cover: oldest-first
   evict, per-unit isolation, node backstop + stray sweep, DRY_RUN deletes nothing
   (at BOTH the evict() and full sweep() level — a broken DRY_RUN deletes fleet
   data), files vanishing mid-scan, unit-depth boundary, empty-cache safety.
2. **`make test` target — make it SELF-BOOTSTRAP a venv, don't assume ambient
   pytest.** A service repo often has no Makefile; add one. But a naive
   `test:\n\t$(PY) -m pytest -q` with `PY?=python3` is a FOOTGUN that bit this
   session: it "passed" only because an unrelated venv was leaking into the shell
   (`VIRTUAL_ENV` unset yet `python3 -c 'import pytest'` worked because an earlier
   `source .venv/bin/activate` from another repo persisted across terminal calls).
   On a CLEAN checkout — exactly the CI-reviewer condition — system `python3` has
   no pytest and `make test` dies with `No module named pytest`. FIX: have the
   target build a throwaway local venv and install pytest into it, so it works on
   any python3 box with zero global deps:
   ```make
   VENV?=.venv
   PY=$(VENV)/bin/python
   test: $(VENV)
   	$(PY) -m pytest -q
   $(VENV):
   	python3 -m venv $(VENV)
   	$(PY) -m pip install -q --upgrade pip
   	$(PY) -m pip install -q pytest
   ```
   Gitignore `.venv/`; add a `clean` target. VERIFY it from a truly clean slate
   (`rm -rf .venv .pytest_cache && make test`) — a green run while an ambient venv
   is active proves NOTHING. GENERAL LESSON: when a test command "passes," confirm
   WHICH interpreter/venv ran it before trusting green; a leaked `source` upstream
   makes a broken target look fine until someone clones cold.
3. **The prod/test manifest split** (above).
4. **Production hardening for a DESTRUCTIVE fleet service** — two safety gaps a
   reviewer will (rightly) block on for anything that deletes files on a shared,
   world-writable (1777) hostPath across every node [2026-07-08]:
   - **Symlink safety.** A 1777 dir means any plugin (or a compromised one) can
     plant a symlink. Naive `os.walk`+`os.stat`+`os.remove` follows link *targets*
     — a symlink to `/etc` gets its target stat'd/counted, and a symlinked *dir*
     lets the walk escape the cache root. FIX in the scanner: `os.walk(root,
     followlinks=False)` (the default, but be explicit) AND prune symlinked
     subdirs (`dirnames[:] = [d for d in dirnames if not
     os.path.islink(join(dirpath,d))]`), use `os.lstat` NOT `os.stat`, and skip
     non-regular files (`if not stat.S_ISREG(st.st_mode): continue`). Net: a
     symlink is never stat'd, counted, traversed, or deleted-through.
   - **Cap-sanity fail-fast at startup.** A ConfigMap typo like
     `PER_NODE_MAX_BYTES: "0"` would make every sweep evict the ENTIRE cache —
     a typo → fleet-wide data loss. Add a `validate_config()` called first in
     `main()` that raises on any non-positive cap/interval/depth, on
     `per_node < per_subdir`, and (in the int parser) on a non-numeric value like
     `"2Gi"` (k8s-style suffixes are NOT bytes) — then `raise SystemExit(2)`. A bad
     cap becomes a loud CrashLoopBackOff an operator notices, never silent
     deletion. Test the matrix (each cap =0, node<subdir, non-numeric env).
   - Note: the non-numeric parse fires at IMPORT (module-level config globals eval
     before `main`'s try/except), so it exits via traceback not the clean log line
     — still non-zero + a readable message, acceptable; refactoring to defer
     parsing isn't worth it for a crash-with-clear-message.
5. **Cut a real version + tag before the handoff ask** [2026-07-08]. A service
   with no `VERSION` and a `:latest` prod-manifest image is a hygiene smell
   (non-reproducible pulls are frowned on in k8s). Add: a `VERSION` file (`0.1.0`),
   pin the PRODUCTION manifest image to `waggle/<svc>:<VERSION>` (not `:latest`),
   a `CHANGELOG.md` with the release entry + a "known limitations (non-blocking)"
   list, and an annotated `git tag -a v0.1.0` pushed with the commit. Deploy the
   node test-add from the TAG (`git checkout v0.1.0`) so what runs live == what a
   reviewer reads.
6. Write a `HANDOFF.md` review checklist: what's done/verified vs what's genuinely
   CI-owned integration work — publishing the image to the registry (the node
   builds it with podman + side-load because ECR buildkit is broken), node-dir
   provisioning in ansible, folding the prod manifest into the kustomize stack, and
   confirming CROSS-USER reads (a 2nd-uid consumer pod reading a producer's files
   under the 1777 sticky dir — the producer side is verifiable solo, the consumer
   side needs a second plugin). List these AS CI-owned; don't block the handoff on
   platform-side infra you don't control.

## End-to-end co-run: real PRODUCER + manager on the SAME shared subtree [VERIFIED live, H00F 2026-07-08]
The final proof for a two-layer cache is a REAL producer plugin writing into the
shared cache while the Layer-2 manager DaemonSet observes the same tree — the
layers must coexist (Layer 1 evicts by policy; Layer 2 stays hands-off under
production caps). Recipe that worked on H00F (image-sampler2 producer +
`wes-local-cache-manager`):
1. **Provision the producer's subdir under the shared root** the manager already
   mounts, then make it pod-writable regardless of the pod's uid:
   `sudo mkdir -p /media/plugin-data/local-cache/<ns>/<plugin>` then
   `sudo chmod 1777` that subdir (and the `<ns>` parent). The manager root is the
   sticky `drwxrwxrwt` dir it created; matching perms let any-uid pod write.
2. **Run the producer with a VOLUME MOUNT of that exact subtree at the cache path
   the plugin auto-detects** — for image-sampler2 the cache resolver is
   `--cache-root > $IS2_CACHE_ROOT > /local-cache (if isdir) > /tmp`, so mounting
   `-v /media/plugin-data/local-cache/<ns>/<plugin>:/local-cache` means NO
   `--cache-root` flag is needed; the ring lands in the shared tree automatically.
   Full bounded run:
   `sudo pluginctl run --selector zone=core --env-from <creds>
     -v /media/plugin-data/local-cache/<ns>/<plugin>:/local-cache -n <name>
     <image-ref> -- --stream <cam> --continuous 8 --cache-max-count 5 --max-runtime 48`
   (bounded so it self-exits cleanly — see `--max-runtime`/`--max-count` in
   `local-cache-ring-buffer.md`).
3. **Confirm Layer 1 (producer ring) from the host** — `sudo ls` the stream dir
   (`.../local-cache/<ns>/<plugin>/<cache-name>/<camera>/`); the file count should
   hold at the ring cap and the plugin log shows `evicted=1 ring_count=N` once it
   fills. Producer pod GONE after the bounded window = clean exit 0.
4. **Confirm Layer 2 (manager) SEES the tree without evicting** — read the
   manager's own sweep log: `sudo k3s kubectl logs -l
   app.kubernetes.io/name=<manager> --tail=12`. It should report the unit count
   climb (`0 units` → `1 units`) and then a real `node_total=<bytes>` matching the
   producer's on-disk size, all `< node cap`/`< per-unit cap` → NO eviction. That
   log line — manager measuring the producer's real bytes and staying hands-off —
   IS the proof the policy-vs-backstop division works live.
5. **Cleanup**: `shred -u` the creds file, `sudo pluginctl rm <name>` any leftover
   pod, `sudo rm -rf .../local-cache/<ns>/<plugin>/*` to restore the empty cache,
   and re-check the manager is still `1/1 Running` at production caps.
The manager needs NO changes for this — it already mounts the parent root, so a new
producer subtree simply appears in its next sweep. Same shape as how upload-agent
picks up any new plugin's uploads dir.

## Local verification without a node (do this before any test-add)
A destructive filesystem service is fully verifiable against a `/tmp` fixture:
build a fake tree (units + a stray file, with staggered mtimes via `touch -d @<epoch>`),
then run `CACHE_ROOT=/tmp/fix RUN_ONCE=1 [DRY_RUN=1] <caps> python3 sweeper.py`
and assert on what remains. Confirm: dry-run deletes nothing; per-unit cap evicts
the oldest in the OVER-cap unit and leaves the under-cap unit; node cap sweeps
across everything incl. the stray, landing at/under the cap.
SHELL TRAP that faked failures this session: env vars passed via `"$@"` expansion
in a wrapper function are NOT honored as assignment prefixes (POSIX: only literal
`VAR=val cmd` words count) — python ran with NO env and "deleted nothing," looking
like a code bug. FIX: prefix with `env`: `run(){ env CACHE_ROOT="$D" "$@" python3 …; }`.
When an ad-hoc test "fails," suspect the harness before the artifact — a literal-env
case passing while an expanded-env case fails is the tell.
SECOND heredoc variant of the same class (hit right after): a single-quoted
heredoc `python3 - <<'PY'` does NOT expand shell vars, so `open('$ROOT/...')`
inside it is the literal string `$ROOT/...` → false `FileNotFoundError`. FIX: pass
paths as ARGV (`python3 - "$ROOT/file" <<'PY'` then read `sys.argv[1]`), or write
`$ROOT` via an EXPANDED pre-heredoc line before the quoted body. Both traps share
one root cause: assuming shell expansion happens where it doesn't. When refreshing
stale verification after a trivial edit, re-run the WHOLE ad-hoc script (not a
mental diff) — the harness bug, not the artifact, was wrong both times this session.
