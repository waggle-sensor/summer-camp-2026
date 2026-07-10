# Direct Node Testing (No Docker / No ECR)

Test plugins directly on a Thor/Spark node via Python — bypassing Docker builds and ECR submission. Fastest iteration loop.

## Important: Official Sage Policy

The Sage documentation explicitly warns:

> ⚠️ Do not run any app or install packages directly on the node. Use Docker container or `pluginctl` commands.

The intended workflow is:
1. Develop locally (your own machine)
2. SSH to a dev node
3. `git clone` your repo
4. `sudo pluginctl build .` (builds Docker image from Dockerfile)
5. `pluginctl run --name test-run <image>` (runs container with GPU access)
6. `pluginctl logs <plugin-id>` (check output)

However, Thor/SGT nodes may not have the full Waggle Edge Stack (k3s) running, making `pluginctl` unavailable. In that case, direct Python testing or Docker containers are the fallback.

## SSH Access

Thor node H00F: `ssh beckman@node-H00F.sage`

## Check Node Capabilities First

```bash
# Is pluginctl available?
which pluginctl

# Is k3s running? (pluginctl depends on it)
pluginctl ps
# If this times out (e.g. "dial tcp 10.31.81.1:6443: i/o timeout"),
# k3s isn't running and pluginctl won't work.

# Can you access the GPU directly?
python3 -c "import torch; print(torch.cuda.is_available())"

# If False, check /dev/nvmap permissions (Tegra-specific)
ls -la /dev/nvmap
# If cr--r----- root:video, you need video group membership
groups
getent group video
```

## Option 1: pluginctl (Preferred — If k3s Is Running)

```bash
cd ~/sage-edge-plugins/plugins/yolo-object-counter
sudo pluginctl build .
pluginctl run --name test-yolo <image> -- --stream bottom_camera --continuous N
pluginctl logs test-yolo
pluginctl rm test-yolo
```

## Option 2: Docker Container (If pluginctl Unavailable)

```bash
docker run --rm -it --runtime=nvidia \
    -v ~/sage-edge-plugins:/app/sage-edge-plugins \
    -w /app/sage-edge-plugins \
    nvcr.io/nvidia/pytorch:25.08-py3 \
    bash

# Inside the container:
pip install pywaggle[all] ultralytics opencv-python-headless
export PYWAGGLE_LOG_DIR=./output/yolo-test
python3 plugins/yolo-object-counter/app.py \
    --image-dir plugins/yolo-object-counter/tests/test-images \
    --continuous N
```

## Option 3: Direct Python (Requires video Group)

Only works if your user is in the `video` group (for `/dev/nvmap` access on Tegra nodes).

### Upload Code

```bash
export THOR=user@thor-hostname
rsync -avz --exclude '.git' --exclude '__pycache__' --exclude '*.pyc' \
  --exclude 'tests/.venv' --exclude '*.pt' --exclude '*.safetensors' \
  ~/AI-projects/Sage-agents/ $THOR:~/sage-edge-plugins/
```

### Run Plugins Directly

All three patterns use PYWAGGLE_LOG_DIR to capture output locally. **This env var is REQUIRED** — without it, pywaggle tries to write to `/run/waggle/uploads/` which only exists on real Sage nodes.

```bash
source venv/bin/activate
export PYWAGGLE_LOG_DIR=./output/run-name

# YOLO — batch (--image-dir) or single (--stream path/to/img.jpg)
python3 plugins/yolo-object-counter/app.py \
  --image-dir plugins/yolo-object-counter/tests/test-images --continuous N

# BioCLIP — same pattern
python3 plugins/bioclip-species-classifier/app.py \
  --image-dir plugins/bioclip-species-classifier/tests/test-images --continuous N

# vLLM — no --image-dir, uses --stream for single image
python3 plugins/vllm-edge-inference/app.py \
  --stream plugins/vllm-edge-inference/tests/test-images/test-image001.jpg \
  --continuous N --enforce-eager --gpu-mem-frac 0.58
```

### Thor GPU Access: /dev/nvmap Permissions

On Thor nodes, `torch.cuda.is_available()` may return False even when the GPU is visible. The root cause is `/dev/nvmap` (Tegra memory manager):

```
$ ls -la /dev/nvmap
cr--r----- 1 root video 10, 123 Jan  1  1970 /dev/nvmap

$ getent group video
video:x:44:gdm,gnome-initial-setup,sage,ollama
```

The `sage` user has access (that's how containers run), but developer users don't. Fix:
```bash
sudo usermod -aG video beckman
# Then log out and back in, or: newgrp video
```

The `NvRmMemInitNvmap failed: Permission denied` stderr messages ARE the actual failure — they're not harmless noise.

### Note on Model Downloads

When running `python3 app.py` directly (not in Docker), Ultralytics auto-downloads model weights (`yolo11x.pt`, ~130MB) to the current directory on first use. This is expected — the Dockerfile bakes the model in so production containers never download. The download is a one-time cost.

## Test Images

Each plugin ships with real test images in `plugins/<name>/tests/test-images/` (committed to git, flat directory). No synthetic generation step needed.

## Samba for Remote File Browsing (Mac Finder over Tailscale)

Mount the node's home directory on a Mac for browsing files, viewing JPGs in Quick Look, etc.

### Setup on the node

```bash
sudo apt install -y samba
```

Add to `/etc/samba/smb.conf` under `[global]`:
```ini
   hosts allow = 100.64.0.0/10 127.0.0.1
   hosts deny = 0.0.0.0/0
   veto files = /._*/.DS_Store/
   delete veto files = yes
```

The `veto files` directive prevents macOS Finder from creating `._*` resource forks and `.DS_Store` files on the server.

**Do NOT use** `bind interfaces only = yes` with `interfaces = tailscale0` — Tailscale's point-to-point interface lacks broadcast capability.

Add a share section:
```ini
[beckman]
   comment = Home Directory
   path = /home/beckman
   browseable = yes
   read only = no
   valid users = beckman
   create mask = 0644
   directory mask = 0755
```

```bash
sudo smbpasswd -a beckman
sudo systemctl enable --now smbd
```

### Connect from Mac

Finder → Cmd+K → `smb://<tailscale-ip>/beckman`

## Cleanup Before Transfer

Run `./clean.sh` (or `./clean.sh --force`) from the repo root to remove test outputs, downloaded model weights, Python caches, macOS `._*` and `.DS_Store` files, and `.pytest_cache`.
