#!/usr/bin/env bash
# on-node pluginctl verify helper for Sage/Waggle plugins (Thor/Blade nodes).
# Runs the build -> import -> smoke steps, then prints the launch/prove/clean
# commands for you to run with real args (creds + plugin flags are task-specific).
#
# Usage (ON the node, e.g. ssh USER@node-<VSN>.sage):
#   onnode-verify-loop.sh <git_url> <image:tag> [commit]
#
# Encodes the pitfalls from references/pluginctl-sideload-and-node-build.md:
#   - podman needs XDG_RUNTIME_DIR
#   - `sudo pluginctl` (namespace RBAC); `--selector zone=core` for volume mounts
#   - --help smoke run catches Dockerfile COPY drift (ModuleNotFoundError)
set -euo pipefail

GIT_URL="${1:?usage: onnode-verify-loop.sh <git_url> <image:tag> [commit]}"
IMG="${2:?need image:tag, e.g. localhost/image-sampler2:0.3.0-rc}"
COMMIT="${3:-}"

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
BUILD=/tmp/onnode-build

echo "== 1. fresh checkout =="
rm -rf "$BUILD"
git clone -q --depth 1 "$GIT_URL" "$BUILD"
cd "$BUILD"
[ -n "$COMMIT" ] && git checkout -q "$COMMIT"
echo "HEAD=$(git rev-parse --short HEAD)"

echo "== 2. podman build + import into k3s containerd =="
podman build -t "$IMG" .
podman save "$IMG" -o /tmp/onnode-img.tar
sudo k3s ctr images import /tmp/onnode-img.tar
rm -f /tmp/onnode-img.tar
sudo k3s ctr images ls | grep -F "${IMG#localhost/}" || { echo "IMPORT FAILED"; exit 1; }

echo "== 3. SMOKE: --help proves all imports load (catches COPY drift) =="
sudo pluginctl run -n onnodesmoke "$IMG" -- --help >/tmp/onnode-smoke.log 2>&1 || true
sleep 8
sudo pluginctl logs onnodesmoke 2>&1 | tail -5
sudo pluginctl rm onnodesmoke >/dev/null 2>&1 || true

NODE_LABELS=$(sudo k3s kubectl get node -o jsonpath='{.items[0].metadata.labels}' 2>/dev/null || true)
echo "== node labels (pick a --selector, e.g. zone=core) =="
echo "$NODE_LABELS" | tr ',' '\n' | grep -E 'zone|resource|hostname' || true

cat <<EOF

== 4-8. RUN / PROVE / CLEAN (fill in task-specific args) ==

# host-mounted cache (observable from host; NOT under /run/waggle/uploads):
sudo mkdir -p /media/plugin-data/SCRATCH && sudo chmod 777 /media/plugin-data/SCRATCH

# creds env-only, mode 600 (never argv/history):
umask 077; printf 'CAMERA_USER=%s\nCAMERA_PASSWORD=*** "\$U" "\$P" > /tmp/cam.env

# launch (backgrounded for forever-plugins); LABEL selector required for -v mount:
nohup sudo pluginctl run -n JOB --selector zone=core \\
  --env-from /tmp/cam.env -v /media/plugin-data/SCRATCH:/cache \\
  $IMG -- PLUGIN_ARGS > /tmp/launch.log 2>&1 &

# observe:
sudo pluginctl logs JOB | tail
ls -la /media/plugin-data/SCRATCH/...

# PROVE in the data plane (local-only plugins still publish measurements):
START=\$(date -u -d '20 minutes ago' +%Y-%m-%dT%H:%M:%SZ)
curl -s -X POST https://data.sagecontinuum.org/api/v1/query \\
  -H 'Content-Type: application/json' \\
  -d "{\"start\":\"\$START\",\"filter\":{\"name\":\"env.YOURTOPIC\"}}"

# tear down + clean:
sudo pluginctl rm JOB
shred -u /tmp/cam.env
sudo rm -rf /media/plugin-data/SCRATCH $BUILD /tmp/launch.log
sudo k3s kubectl get pods -n default | grep wes-plugin-scheduler   # unharmed?
EOF
