# Node SSH access routes + probing gpsd / GPS on WSNs

Reusable knowledge for reaching Sage fleet nodes and inspecting their GPS chain.
Learned probing W09E/W08B/W06C/W0A4 for a live gpsd fix (2026-07-08).

## Two DIFFERENT SSH routes — pick the right one per node

1. **Thor nodes (any VSN starting with `H`) — the SIMPLE route:**
   `ssh USER@node-<VSN>.sage`   (substitute the VSN, keep the `H` prefix)
   - This is the general pattern for the **new "Thor" ARM64 nodes** (H-prefix VSNs),
     NOT a per-node special case. If the VSN begins with `H`, use this route.
   - Uses `~/.ssh/config` `Host *.sage` -> `ProxyJump sage-vpn` (vpn.sagecontinuum.org).
     No beekeeper gateway, no lowercase-vsn dance — just the direct `.sage` name.
   - User `beckman` has **passwordless sudo** -> full k3s/kubectl/docker.
     (`sudo -n true` succeeds; `sudo kubectl ...` works directly.)
   - Verified live on H00F 2026-07-12: `ssh USER@node-<VSN>.sage` lands as user
     `beckman` on host `sgt-thor-<serial>-H00F`; `/etc/waggle/vsn`=H00F,
     `/etc/waggle/node-id`=00004CBB4701D16C; k3s **v1.34.2+k3s1** (client+server),
     `sudo kubectl` returns cluster version with no password prompt.
   - Contrast with route 2: Thor H-nodes do NOT go through `waggle-dev-sshd`; the
     old NX/WSN nodes (W-prefix) DO. Prefix tells you the route: `H*` = route 1,
     `W*`/`V*` = route 2.

2. **General fleet nodes (WSNs), via the beekeeper gateway:**
   `ssh waggle-dev-node-<LOWERCASE-vsn>`   e.g. `ssh waggle-dev-node-w08b`
   - Pete's explicit form for the older NX nodes: **`ssh waggle@waggle-dev-node-w09e`**
     (spell out `waggle@`). The config's `Host waggle-dev-node-*` already sets
     `User waggle`, so the bare form usually works too, but use the `waggle@` form
     when a node is finicky.
   - Config `Host waggle-dev-node-*` runs
     `ProxyCommand ssh waggle-dev-sshd connect-to-node $(sed s/waggle-dev-node-//)`.
   - **The vsn MUST be lowercase.** Uppercase (`...-W08B`) makes `connect-to-node`
     fail to match — you get the gateway welcome banner but the session to the node
     never opens ("Session open refused by peer" / command silently doesn't run).
   - You log in as user **`waggle`** (uid 1000), **NO passwordless sudo**
     (`sudo -n true` -> "a password is required"). Do NOT guess the password.

### Diagnosing a route
- `Stdio forwarding request failed: Session open refused by peer` on `<node>.sage`
  = that node's VPN/beehive reverse tunnel isn't up right now (node offline / not
  phoning home) OR you used the wrong route. Test the jump host alone:
  `ssh sage-vpn 'hostname'` and a known-good node (`ssh USER@node-<VSN>.sage echo ok`).
- Gateway greets you ("Welcome to our node SSH gateway") but your command produces
  no output = the `connect-to-node` arg didn't resolve. Verify with:
  `ssh waggle-dev-sshd connect-to-node <lowercase-vsn>` — it prints
  "connecting you to node W09E (000048B0...)" and the node's SSH banner when correct.

## What you CAN do as plain `waggle` (no sudo)

- Read world-readable node metadata: `/etc/waggle/node-manifest-v2.json` (0644),
  `/etc/waggle/node-id`, `/etc/waggle/vsn`. The manifest lists GPS hardware and
  surveyed `gps_lat`/`gps_lon` (may be **null = node not yet surveyed**, e.g. W09E).
- See the host process table: `ps -ef | grep -i gpsd` reveals whether a gpsd is
  running (even the pod's, as it shows on the host PID namespace).
- `systemctl is-active gpsd` (host service — usually `inactive` on WSNs; gpsd runs
  in a pod, not as a host unit).
- `ls -l /dev/ttyACM* /dev/ttyUSB*` — the GPS dongle appears here (Geekstory VK-162
  USB on the probed WSNs).

## What you CANNOT do as plain `waggle` (all need root)

- `k3s kubectl ...` — kubeconfig `/etc/rancher/k3s/k3s.yaml` is root-only (0600).
- `docker ps` / docker socket — permission denied.
- `crictl` — crictl.yaml permission denied.
- `nsenter` into the gpsd pod's net namespace — `/proc/<pid>/ns/net` root-only.

BUT: not having cluster tooling does NOT block reading gpsd — the pod IP is
routable on the flannel net directly from the host (see the live-GPS section
below). Don't conclude "gpsd is unreachable without root."

## Reading a live GPS (gpsd / TPV) fix — the crux (SOLVED without root)

- On WSNs, gpsd runs **inside the `wes-gps-server` pod**, serving the gpsd JSON
  protocol on **:2947** (`wes-gps-server.default.svc.cluster.local:2947` in-cluster).
  Observed: `/usr/sbin/gpsd -N -n -G -D 5 /host/dev/gps` (runs as `nobody`, gpsd
  **3.17**). The `-G` flag = listen on all interfaces, so it's bound on the pod's IP.
- **KEY WIN (2026-07-08, confirmed on W09E): you do NOT need root/kubectl/sudo.**
  The gps-server pod's IP on the **flannel pod network is directly routable from the
  node host**, so a plain socket from the `waggle@` shell reaches :2947. Earlier
  belief that "host user cannot reach it, needs a probe pod" was WRONG — that only
  applies to the *DNS name* (cluster-DNS is pod-only) and to host-IP :2947 (refused).
  Hit the **pod IP** instead.
- **Working recipe (no sudo):**
  1. `ip route` -> find the pod CIDR (`10.42.0.0/24 dev cni0 ... src 10.42.0.1`).
  2. `ip neigh | grep 10.42 | awk '{print $1}'` -> list live pod IPs on this node.
  3. Scan them for an open :2947 (short-timeout socket connect). One will be the
     gps-server pod (e.g. `10.42.0.128:2947 OPEN`). **NOTE: flannel pod IPs are
     EPHEMERAL** — they change on pod restart, so re-scan each time; never hardcode.
  4. Speak gpsd JSON: connect, read the `VERSION` banner, send
     `?WATCH={"enable":true,"json":true};\n`, then read lines for `"class":"TPV"`
     (position: `lat`/`lon`/`alt`/`mode`/`time`) and `"class":"SKY"` (satellite
     count + `hdop`). `mode`: 0 unknown / 1 no-fix / 2 = 2D / 3 = 3D.
- **You still CANNOT read NMEA off the device directly:** gpsd opens `/dev/ttyACM0`
  (= `/dev/gps`, u-blox 7, VID:PID `1546:01a7`) with `-N -n`, so a raw device read
  returns `Device or resource busy`. The gpsd socket is the ONLY path to the fix —
  which is exactly why a library wrapper (pywaggle2 `GPS().watch()`) is the right
  design, not per-plugin device reads.
- **Observed jitter:** 8 TPV fixes in ~2s on a pole-mounted (static) W09E wandered
  at the ~1e-7–1e-6° level (≈cm–2 m) with zero motion. Fix quality was 3D, 16 sats
  seen / 10 used, HDOP 0.81. So a consumer wanting a stable point should
  average/median a short window, not trust a single reading.

## Two-axes reminder (see pywaggle2-design.md §2.2.1)

- **Deployment mobility** (pole vs. vehicle) is separate from **GPS-fix liveness**
  (does a receiver+gpsd emit fresh fixes). A *static* pole-mounted WSN can have a
  perfectly *live* gpsd whose lat/lon jitters by cm (receiver noise, not motion).
- Therefore the gpsd/live-stream code path IS testable on a static node with a live
  receiver — no mobile hardware needed. Only the deployment-mobility *semantics*
  (fix that truly moves) require an actual mobile node.
- For NodeInfo on a static deployment: the **surveyed manifest coordinate is
  authoritative**; a live-but-jittering fix is deliberately ignored (don't report
  drifting coords for a fixed asset).

## Fleet facts confirmed 2026-07-08
- W09E/W08B/W06C/W0A4 all carry Geekstory **VK-162 USB GPS**, manifest
  `is_active: true`, scope nxcore.
- W08B had a live gpsd process serving; dongles at /dev/ttyACM0, /dev/ttyUSB0-4.
- Surveyed coords: W08B 41.822952,-87.609693 · W06C 43.940154,-110.644137 ·
  W0A4 41.701598,-87.995233 · **W09E null (unsurveyed)** — good edge case for the
  "location unknown -> return None, omit EXIF GPS, never fabricate" rule.

## Fleet facts confirmed 2026-07-09
- **W096** = old-style login node, reached cleanly via `ssh waggle@waggle-dev-node-w096`
  (lowercase vsn, as always). Manifest world-readable at 0644 — no sudo needed to
  read it. W096 is a **LoRaWAN node** (9 `lorawanconnections` — sap-flow meters +
  S-node) — the reference node for manifest-sensitivity work (see
  `wes-pod-config-and-manifest-exposure.md`). Chicago (1020 S Union Ave).
