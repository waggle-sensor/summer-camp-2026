# Docker Build & Deploy for Sage Edge Plugins

## Base Image Selection (Critical for Blackwell)

DGX Spark and Thor have DIFFERENT compute capabilities despite both being "Blackwell":
- **DGX Spark**: GB10, sm_121 (CC 12.1)
- **Thor nodes**: NVIDIA Thor / Jetson Thor, sm_110 (CC 11.0)

| Image Tag | CUDA | PyTorch | GPU Support | Notes |
|-----------|------|---------|-------------|-------|
| `25.08-py3` | 13.0 | 2.8 | **sm_110 (Thor) + sm_120/sm_121 (DGX Spark)** | **Recommended — covers both** |
| `25.04-py3` | 12.9 | 2.7 | sm_120/sm_121 only — **NO sm_110** | ⚠️ Fails on Thor |
| `25.03-py3` | 12.8.1 | 2.7 | sm_120 only | No Thor support |
| `25.01-py3` | 12.8 | 2.6 | sm_120 (first) | Minor caveats |
| `24.06-py3` | 12.4 | 2.4 | sm_90 max | ❌ Fails on DGX Spark AND Thor |

Using the wrong base image:
- **25.04 on Thor**: "NVIDIA Thor with CUDA capability sm_110 is not compatible" warning, CPU fallback
- **24.06 on DGX Spark**: "GB10 with CUDA capability sm_121 is not compatible", silent CPU fallback

All NGC containers are multi-arch (amd64 + arm64 SBSA). The `pytorch/pytorch:*`
Docker Hub images are amd64-only — do NOT use on ARM64 nodes.

## Protecting Base Image Packages (Critical)

The NVIDIA base image ships:
- PyTorch compiled with Blackwell GPU kernels (e.g. `torch==2.8.0a0+34c6371d24.nv25.08`)
- torchvision matching that torch
- numpy 1.26.4 (torch's C extensions are compiled against numpy 1.x ABI)

pip must NOT upgrade any of these. `ultralytics` depends on torch/torchvision/numpy
and will pull generic PyPI versions that break GPU inference.

**Symptoms of broken torch**: `RuntimeError: GET was unable to find an engine`
**Symptoms of broken numpy**: `RuntimeError: Numpy is not available` from `torch.from_numpy()`

**Fix**: Constraints file that freezes all three:

```dockerfile
RUN pip install --no-cache-dir --upgrade pip && \
    TORCH_VER=$(python3 -c "import torch; print(torch.__version__)") && \
    TV_VER=$(python3 -c "import torchvision; print(torchvision.__version__)") && \
    NP_VER=$(python3 -c "import numpy; print(numpy.__version__)") && \
    echo "Freezing base-image stack: torch==${TORCH_VER} torchvision==${TV_VER} numpy==${NP_VER}" && \
    printf "torch==${TORCH_VER}\ntorchvision==${TV_VER}\nnumpy==${NP_VER}\n" > /tmp/constraints.txt && \
    pip install --no-cache-dir -c /tmp/constraints.txt -r requirements.txt
```

Key points:
- Remove `torch` AND `numpy` from requirements.txt (base image provides both)
- Freeze torch + torchvision + numpy (all three matter)
- 25.08-py3 does NOT include torchaudio — don't try to freeze it
- Use `-c /tmp/constraints.txt` on ALL pip install commands (including opencv fix)
- Dynamic approach reads versions at build time — works with any base image
- Verify: `pip list | grep torch` should show `.nv25.` in the version

## OpenCV Fix (Required in All Dockerfiles)

```dockerfile
RUN pip uninstall -y opencv-python opencv-python-headless 2>/dev/null; \
    rm -rf /usr/local/lib/python3.*/dist-packages/cv2* && \
    pip install --no-cache-dir -c /tmp/constraints.txt opencv-python-headless>=4.8.0
```

Uses `-c /tmp/constraints.txt` from the constraints step above.

Why each piece matters:
- `pip uninstall`: removes pip's record of the GUI opencv
- `rm -rf cv2*`: removes stale .so files pip uninstall misses
- `python3.*` glob: works across Python versions (3.10, 3.12)
- headless variant: no GUI deps needed on edge nodes

## Docker Runtime: --runtime=nvidia (Not --gpus all)

**Always use `--runtime=nvidia`** in documentation, scripts, and docs.

Thor nodes use an older NVIDIA Container Runtime Hook that does NOT support
`--gpus all` — it errors with:
```
invoking the NVIDIA Container Runtime Hook directly (e.g. specifying the docker
--gpus flag) is not supported. Please use the NVIDIA Container Runtime instead
```

`--runtime=nvidia` works on BOTH DGX Spark and Thor. Use it everywhere.

### NVIDIA Container Toolkit Setup (One-Time, Build Machine)

Docker needs the toolkit **configured** (not just installed):

```bash
# Quick check:
docker run --rm --runtime=nvidia nvidia/cuda:12.9.0-base-ubuntu24.04 nvidia-smi

# If it fails — configure (one-time):
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
docker info | grep -i runtime  # nvidia must appear
```

Thor has this pre-configured. Dev machines need the one-time setup.

## Build Workflows

### Option A: Build on DGX Spark, Transfer to Thor

```bash
cd ~/sage-yolo
docker build --no-cache -t yolo-object-counter:0.2.0 .

# Test locally first
mkdir -p ~/yolo-test-output
docker run --rm --runtime=nvidia \
    -v ~/sage-yolo/tests/test-images:/images:ro \
    -v ~/yolo-test-output:/output \
    -e PYWAGGLE_LOG_DIR=/output \
    yolo-object-counter:0.2.0 \
    --image-dir /images --continuous N

# Transfer
docker save yolo-object-counter:0.2.0 | gzip > /tmp/yolo.tar.gz
scp /tmp/yolo.tar.gz user@thor-node:~/
# On Thor:
sudo docker load < ~/yolo.tar.gz
```

### Option B: Build Directly on Thor (Fastest Iteration)

If Thor has Docker + internet access:

```bash
git clone https://github.com/flint-pete/sage-yolo.git /tmp/sage-yolo
cd /tmp/sage-yolo
sudo docker build --no-cache -t yolo-object-counter:0.2.0 .

# Test
sudo docker run --rm --runtime=nvidia \
    -v /tmp/sage-yolo/tests/test-images:/images:ro \
    -e PYWAGGLE_LOG_DIR=/tmp/test-output \
    yolo-object-counter:0.2.0 \
    --image-dir /images --continuous N

# Iterate: edit on dev → git push → on Thor: git pull && sudo docker build
```

All Docker commands on Thor require `sudo`.

**Long builds via SSH: use `nohup` to survive disconnections.** SSH ControlPersist
timeouts and agent expiration kill connections during multi-minute builds. Run the
build detached on Thor so it continues regardless of SSH state:

```bash
# Start build in background on Thor (survives SSH disconnect)
ssh USER@node-<VSN>.sage "cd /tmp/sage-bioclip && \
    nohup sudo docker build --no-cache -t bioclip-species:0.2.0 . \
    > /tmp/bioclip-build.log 2>&1 &"

# Check progress from any new SSH session
ssh USER@node-<VSN>.sage "tail -5 /tmp/bioclip-build.log"

# Same for k3s import (also slow — ~6 min for 22GB image)
ssh USER@node-<VSN>.sage "nohup bash -c \
    'sudo docker save bioclip-species:0.2.0 | sudo k3s ctr images import - \
    > /tmp/bioclip-import.log 2>&1 && echo IMPORT_DONE >> /tmp/bioclip-import.log' &"
```

This avoids the pattern of starting a foreground SSH command that dies when the
control master expires (especially common with ProxyJump + ControlPersist 10m
and passphrase-protected keys that depend on ssh-agent).

### Deploy via pluginctl

```bash
sudo pluginctl deploy -n yolo-counter docker.io/library/yolo-object-counter:0.2.0 \
    -- --stream bottom_camera --continuous N
pluginctl logs yolo-counter
sudo pluginctl rm yolo-counter
```

**Always `pluginctl rm` before re-deploying the same name.** Re-running
`pluginctl deploy` with the same `-n NAME` while a pod already exists triggers
a Kubernetes in-place patch, which the API server rejects:

```
Error: Pod "NAME" is invalid: spec: Forbidden: pod updates may not change
fields other than `spec.containers[*].image`, ... (only additions to existing
tolerations), ...
```

k8s only allows the image field (and a few others) to change on a running pod;
any volume/args/env change is forbidden. Fix:

```bash
sudo pluginctl rm NAME           # delete the old pod first
# wait a few seconds for it to terminate, then redeploy
# if stuck Terminating:
sudo kubectl delete pod NAME --grace-period=0 --force
```

**Args (camera URL, --duration, --min-confidence, etc.) are passed at deploy
time, NOT baked into the image.** Changing a camera URL or threshold needs only
a re-deploy with new args — NO rebuild. Rebuild only when app.py, the Dockerfile,
or dependencies change (or you bump the version tag).

**Quote camera URLs in single quotes.** Passwords with `!` trigger bash history
expansion under double quotes; `&` and `?` are shell metacharacters. Single
quotes protect all of them: `--camera 'http://...&user=U&password=P!'`.

### Force a fresh pull on a node (same tag re-pushed)

Pulling the same tag (e.g. `:0.1.0`) normally serves the cached copy. To force
a genuinely fresh fetch after someone re-pushed over a tag (a new tag like
`:0.2.0` is always fetched clean — this dance is only for reused tags):

```bash
# k3s runtime (what pluginctl uses):
sudo k3s ctr images rm registry.sagecontinuum.org/NS/PLUGIN:TAG
sudo k3s ctr images pull registry.sagecontinuum.org/NS/PLUGIN:TAG
sudo k3s ctr images ls | grep PLUGIN     # verify fresh timestamp

# Docker (if testing with docker): always re-checks registry digest
sudo docker pull registry.sagecontinuum.org/NS/PLUGIN:TAG
```

ECR namespace note: the registry namespace (e.g. `beckman`) can differ from the
GitHub org (e.g. `flint-pete`). The image ref uses the ECR namespace; only
`sage.yaml` source.url/homepage use the GitHub org.

## Publishing to Sage ECR

ECR is NOT a Docker registry you push to. It pulls from GitHub and builds for you.

1. Code in a public GitHub repo with `sage.yaml`, `Dockerfile`, `ecr-meta/`
2. portal.sagecontinuum.org → My Apps → Create App → enter repo URL
3. ECR builds and assigns: `registry.sagecontinuum.org/user/plugin:version`

ECR requires one repo per plugin (can't target subdirectories in monorepos).
