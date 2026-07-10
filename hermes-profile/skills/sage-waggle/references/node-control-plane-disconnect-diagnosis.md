# Diagnosing "a plugin stopped reporting" — node control-plane disconnect

When a plugin's data stops appearing in the Beehive/data API, work the data
plane FIRST, then the node. The most common non-code cause is that the NODE lost
its connection to the k3s control plane after a reboot — the plugin code is fine.

## Step 1 — Data plane: is it a dropout or a full stop? (definitive first cut)

Query the plugin's per-cycle HEARTBEAT topic, not just its detection topic. Every
one of these plugins publishes an every-cycle heartbeat (`env.count.total`,
`plugin.duration.inference`, `env.detection.audio.summary`, `env.species.summary`).

```python
import json, urllib.request
def q(name, vsn, start="-96h"):
    body={"start":start,"filter":{"vsn":vsn,"name":name}}
    req=urllib.request.Request("https://data.sagecontinuum.org/api/v1/query",
        data=json.dumps(body).encode(),headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req,timeout=60) as r:
        recs=[json.loads(l) for l in r.read().decode().splitlines() if l.strip()]
    ts=sorted(x["timestamp"] for x in recs)
    return len(recs), (ts[0][:19], ts[-1][:19]) if ts else None
```

Interpretation:
- Detection topic quiet but heartbeat still ticking -> real detection dropout
  (sampling/threshold/subject issue). Investigate the plugin.
- **Heartbeat AND detections stop at the SAME instant -> the process stopped
  running entirely.** Not a plugin bug. Go to Step 2.
- If ALL of the node's plugins stop at the same instant -> node-level cause
  (reboot / control-plane loss), not any single plugin.

Times are UTC. Central (CDT) = UTC-5. (e.g. "11:04am CDT" = 16:04 UTC).

## Step 2 — Correlate with a node reboot

```
ssh beckman@node-H00F.sage 'hostname; uptime'
```

If `uptime` shows the node came up right when reporting stopped, a reboot is the
trigger. The node can be fully SSH-reachable (over the Tailscale/VPN path) and
still be cut off from its cluster control plane.

## Step 3 — THE DEFINITIVE TEST: can kubectl reach the API server?

Run ON the node. This is the single command that proves control-plane reach:

```
ssh beckman@node-H00F.sage 'sudo kubectl get pods -n ses --request-timeout=30s'
```

- Success (pod list) -> control plane reachable; look elsewhere.
- **`dial tcp 10.31.81.1:6443: i/o timeout` (or `http2: client connection lost`)
  -> control plane UNREACHABLE from this node.** `10.31.81.1:6443` is the
  in-cluster API-server VIP. On a Waggle/Thor node the API server / WES control
  plane is REMOTE; kubelet runs pods locally but needs the API to (re)launch
  them. No API => SES cannot place/restart pods => every plugin stays dark.

Caveat on scope: the kubectl timeout proves "unreachable from this node" but does
not alone distinguish (a) API down, (b) network path broken, (c) wrong endpoint.
Corroborate with Steps 4-5.

More surgical transport-only probe (independent of kubectl/cert/kubeconfig):
```
ssh beckman@node-H00F.sage 'timeout 8 bash -c "</dev/tcp/10.31.81.1/6443" && echo OPEN || echo UNREACHABLE'
```

## Step 4 — Isolate node-local vs cluster-wide (avoid wrong escalation)

Check whether the rest of the fleet is healthy. Every node's nodeware publishes
`sys.uptime`; query it fleet-wide (no vsn filter) for the last 15m and list the
`meta.vsn` values.

- Many nodes present, target node ABSENT -> node-LOCAL failure. The node isn't
  even publishing its own nodeware to Beehive; it's isolated while alive locally.
  Fix is node-local recovery (Step 6), NOT an ops-wide escalation.
- Target present / whole fleet quiet -> cluster-wide; escalate to Sage/WES ops.

## Step 5 — Node-side corroboration

```
ssh beckman@node-H00F.sage '
  sudo systemctl is-active k3s          # often "active" even when link is dead
  ip route get 10.31.81.1               # route present? (via ... dev wan0)
  sudo wg show                          # wg-sage handshake recent? traffic flowing?
  sudo journalctl -u k3s --since "<reboot time>" --no-pager |
    grep -iE "6443|client connection lost|dial|lease|apiserver|x509|tls" | tail
'
```

Telltale signature of this failure: k3s `active`, WireGuard healthy (recent
handshake, bytes moving), route to the VIP exists — but the journal shows
`http2: client connection lost` degrading to `dial tcp 10.31.81.1:6443:
i/o timeout`, failed node-lease updates, and pods unable to mount their
service-account tokens (`failed to fetch token ... 6443`). The link was up before
the reboot and never re-converged.

## Step 6 — Recovery (get user consent first; production node, real blast radius)

Usual cure for "k3s up but control-plane link stale after reboot":
```
ssh beckman@node-H00F.sage 'sudo systemctl restart k3s'
```
Then VERIFY IN THE DATA PLANE (standing rule — "Running"/"active" is not proof):
watch `kubectl get nodes` recover, the node lease update, SES repopulate the
plugin pods, and the heartbeat topic (`env.count.total`) resume in the data API.
If it does not reconnect, escalate to Sage/WES ops: "node <VSN> lost its
control-plane link after its <date> reboot" (possible stale TLS/token or a
control-node-side node-registration issue).

## Reusable access facts (verified this session)
- SES token file on Flint: `<YOUR_SAGE_TOKEN_FILE>`
  (read with `read -r TOKEN < <path>`; Hermes mangles `$(cat ...)`).
- Node SSH: `ssh beckman@node-H00F.sage` (uses `*.sage` + sage-vpn ssh config).
  NOT a bare `H00F` hostname.
- `sesctl` may NOT be on PATH in a given shell — verify `which sesctl` before
  trusting an empty `sesctl stat` (an empty grep of a "command not found" error
  looks falsely like "no jobs").
- kubectl on a freshly-cut-off node can hang; give SSH commands a generous
  timeout (bump the terminal tool timeout above its 60s default) and pass
  `--request-timeout=30s` so kubectl fails fast instead of hanging.
