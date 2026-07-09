# Diagnosing a node/plugin that "stopped reporting"

When a user says "plugin X stopped publishing events after <time>", resist the
urge to dig into the plugin code first. Most of the time it is NOT a code bug —
it is the node, the scheduler, or the cluster link. Walk this ladder in order;
each rung narrows the cause and is cheap. Stop when you've localized it.

## The diagnostic ladder (run top-down)

### Rung 1 — Data plane: when EXACTLY did it stop, and did the heartbeat die too?
Query the public data API for the plugin's topics over a window that brackets
the reported time. Crucially, check the **per-cycle heartbeat / telemetry topic**
(`plugin.duration.inference`, `env.count.total`, `env.*.summary`) alongside the
science topic.

```python
import json, urllib.request
def query(name, vsn, start="-96h"):
    body={"start":start,"filter":{"vsn":vsn,"name":name}}
    req=urllib.request.Request("https://data.sagecontinuum.org/api/v1/query",
        data=json.dumps(body).encode(),headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req,timeout=60) as r:
        return [json.loads(l) for l in r.read().decode().splitlines() if l.strip()]
# look at first/last timestamp per topic
```
INTERPRETATION:
- **Heartbeat stops at the SAME instant as the science topic** → the plugin
  PROCESS stopped running entirely. This is the common case → go to Rung 2. It is
  NOT a detection dropout and NOT a threshold/model issue.
- **Heartbeat keeps publishing but the science topic went quiet** → the process
  is alive; it's a real detection/threshold/data problem → THEN look at code,
  thresholds, camera/audio source.
- Remember TZ: data API timestamps are UTC. Central = UTC−5 (CDT). Convert before
  comparing to the user's reported local time.

### Rung 2 — Node uptime: did it reboot at that instant?
```
ssh beckman@node-H00F.sage 'hostname; uptime'
```
(Node SSH is `beckman@node-<VSN>.sage`, via the sage-vpn / `*.sage` ssh config —
NOT a bare `H00F` hostname, which won't resolve.) If `uptime` shows the box came
up right around the silence time, a **reboot** is the trigger. k3s often comes
back as a *service* but fails to re-establish other things → Rung 3.

### Rung 3 — Is the node cut off from the cluster control plane?
The killer test. On a Waggle/Thor node the kubelet runs pods locally but the
**Kubernetes API server / WES control plane is REMOTE**. After a reboot k3s can
be `active` locally yet never reconnect to the API server.
```
ssh beckman@node-<VSN>.sage '
  sudo systemctl is-active k3s
  sudo kubectl get pods -n ses --request-timeout=30s'
```
SMOKING GUN: `dial tcp 10.31.81.1:6443: i/o timeout` /
`http2: client connection lost` / `couldn't get current server API group list`.
`10.31.81.1:6443` is the in-cluster API-server VIP. If kubectl can't reach it:
- SES **cannot place or restart** any pod on the node.
- Pods can't even mount service-account tokens (`failed to fetch token … 6443`).
- → **ALL plugins on that node go dark simultaneously**, not just the one the
  user noticed. Confirm by checking a second plugin's topics also died at the
  same instant.

This is a NODE-INFRASTRUCTURE failure, not a plugin bug. Say so plainly.

Useful corroborating probes (read-only):
```
ip route get 10.31.81.1            # route exists but API still unreachable = link/cert, not routing
sudo wg show                       # wg-sage handshake recent + traffic flowing = VPN fabric OK
sudo journalctl -u k3s --since "<reboot time>" | grep -iE "6443|apiserver|x509|tls|dial|connect"
```

### Rung 4 — Scope: is it just this node, or the whole fleet?
This decides node-local restart vs. ops escalation. Every healthy node publishes
`sys.uptime` (node nodeware). Query it fleet-wide for the last 15 min:
```python
body={"start":"-15m","filter":{"name":"sys.uptime"}}   # POST to the data API
# collect distinct meta.vsn from the results
```
- Many nodes (100+) reporting AND the target VSN ABSENT → the fleet/control
  plane is fine; the problem is **node-local**. Remedy = node-local recovery.
- Target VSN absent from `sys.uptime` too (not just its plugins) → the node's own
  nodeware isn't reaching Beehive either; it's isolated from the cluster while
  still alive locally (you can still SSH in over the VPN). Still node-local.
- Fleet-wide gap → escalate to Sage/WES ops; don't restart anything.

## The fix (get explicit user OK first — production node, real blast radius)
For "k3s active locally but control-plane link stale after reboot," the standard
cure is a clean k3s restart so it re-handshakes with the API server:
```
ssh beckman@node-<VSN>.sage 'sudo systemctl restart k3s'
```
Then VERIFY IN THE DATA PLANE (not "Running" status): `kubectl get nodes` becomes
reachable, the node lease recovers, SES repopulates the plugin pods, and the
science topics resume in the data API. If a restart doesn't reconnect it,
escalate: "node <VSN> lost its control-plane link to 10.31.81.1:6443 after its
<date> reboot" (possible stale TLS/token or control-node-side registration).

## Gotchas hit while doing this
- `sesctl` and `kubectl` may not be in the laptop's PATH / the empty output can be
  a `command not found` swallowed by a grep — check the RAW command output before
  concluding "no jobs." Don't trust a grep over an errored command.
- Don't trust stale memory for token/host paths. The SES token has lived at
  `<YOUR_SAGE_TOKEN_FILE>` (read with
  `read -r TOKEN < …`); node SSH is `beckman@node-<VSN>.sage`. Verify paths exist
  before building commands on them.
- kubectl against an unreachable API hangs for the full `--request-timeout`;
  give the SSH command a generous foreground timeout (≥200s) or it looks like a
  hang when it's just waiting on the timeout you set.
