# Side-loading a WES change onto a node & restoring cleanly

How to prove a WES/scheduler change on a real node BEFORE upstream merge, and the
teardown pitfalls. Learned building/testing wes-nodeinfo-injection on H00F (2026-07).

## Three-gate escalation (validate cheap→expensive, small→large blast radius)

Prove a change that spans config + control-plane in escalating gates so ~90% is
validated at near-zero risk before you touch the scheduler:

- **Gate 1 — ConfigMap / config-only (SAFE, seconds to revert).** Regenerate the CM
  from the node's real manifest, launch a throwaway pod that consumes it via explicit
  `envFrom` and prints the resolved value. Proves the whole read path WITHOUT the
  patched binary. Existing plugins untouched. This is the daily-driver loop.
- **Gate 2 — patched control-plane binary (deliberate).** Build the patched
  scheduler on-node (podman native arm64 — known-good; ECR builder historically
  flaky), `k3s ctr images import`, repoint the Deployment, AUTO-REVERT on failed
  rollout. Proves auto-injection into EVERY normally-scheduled plugin.
- **Gate 3 — real end-to-end (the money shot).** Run an actual plugin (e.g.
  image-sampler2) wired to the change, then verify via the DATA API that the produced
  artifact carried the real effect (e.g. correct geotag). This is the user-facing proof.

Pre-flight before ANY gate: confirm the target resource names on THIS node
(`sudo kubectl -n default get deploy` — scheduler is `wes-plugin-scheduler` on H00F,
1/1). Names vary per node; fail fast with a name check, not mid-rollout.

## Restore == restore-from-backup, NOT delete (mutating change)

When a change MUTATES an existing WES object (ConfigMap, Deployment) rather than
deploying a standalone DaemonSet, "remove" means RESTORE the original, not delete.
Back up ONCE to a gitignored dir (never overwrite a prior backup → safe re-run);
mark absent originals with a sentinel so restore = delete in that case.

## PITFALL (found live on H00F): `kubectl apply -f backup.yaml` restore CONFLICTS

If the add step mutated the object via a NON-apply op — e.g.
`kubectl create configmap X --from-env-file=f --dry-run=client -o yaml | kubectl apply -f -`
— that bumps `resourceVersion` and replaces `.data` OUTSIDE apply's merge base. The
backup YAML carries the ORIGINAL (now-stale) `resourceVersion` +
`last-applied-configuration`, so restoring with `kubectl apply -f backup.yaml` fails:

    Error from server (Conflict): ... the object has been modified;
    please apply your changes to the latest version and try again

→ the object is NOT restored and the backup file is NOT consumed. Node left modified.
`make test`/offline dry-runs with a naive fake kubectl WON'T catch this — the fake
must model a resourceVersion that bumps on every mutation to reproduce the conflict.

## THE ROBUST RESTORE IDIOM (use this, not raw apply)

Restore FROM THE BACKUP as source of truth, via imperative `replace`, after
stripping volatile metadata; fall back to delete+create:

    payload="$(jq 'del(.metadata.resourceVersion, .metadata.uid,
                       .metadata.creationTimestamp, .status,
                       .metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"])' \
                 <(yaml2json backup.yaml))"
    printf '%s' "$payload" | kubectl -n "$ns" replace -f - \
      || { kubectl -n "$ns" delete "$kind" "$name" --ignore-not-found
           printf '%s' "$payload" | kubectl -n "$ns" create -f -; }

`replace` overwrites the full object regardless of the live object's provenance;
stripping `resourceVersion` avoids the optimistic-concurrency conflict; dropping
`last-applied-configuration` keeps a later `apply` from re-merging stale state.
(yaml2json = `python3 -c 'import sys,yaml,json;json.dump(yaml.safe_load(open(sys.argv[1])),sys.stdout)'`.)

## Pod-wait pitfall for throwaway test pods

A `restartPolicy: Never` pod that prints+exits in ~1s often NEVER reports
`Ready=True` (races straight to `Succeeded`). `kubectl wait --for=condition=Ready`
then burns its whole timeout. Wait for a TERMINAL phase instead:
`kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/X --timeout=90s`, with a
short `=Failed` fallback so you still grab logs on error.

## Getting files onto the node

rsync the minimal fileset preserving repo layout so relative paths (`$HERE/..`)
resolve: `rsync -az node-test/ gen-*.sh USER@node-<VSN>.sage:~/proj/...`.
`jq`, `awk`, `python3` are present on Thor nodes.
