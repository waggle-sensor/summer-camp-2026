# pluginctl — camp guide for Thor plugin development

**Camp default on Thor nodes:** build and test Sage plugins with `pluginctl` on the node — not raw `podman build` for your first iteration, and not `python3 app.py` directly on the host.

Official docs:
- [Sage pluginctl reference](https://sagecontinuum.org/docs/reference-guides/pluginctl)
- [edge-scheduler pluginctl tutorials](https://github.com/waggle-sensor/edge-scheduler/tree/main/docs/pluginctl) (README + hello-world, build, logs, env, resources, …)
- [Tutorial: building a plugin](https://github.com/waggle-sensor/edge-scheduler/blob/main/docs/pluginctl/tutorial_build.md)
- [Edge apps tutorial series](https://sagecontinuum.org/docs/category/edge-apps) — intro → create → test → publish to ECR
- **When ready to schedule fleet jobs (`sesctl`):** [Sage sesctl reference](https://sagecontinuum.org/docs/reference-guides/sesctl) · [edge-scheduler sesctl tutorials](https://github.com/waggle-sensor/edge-scheduler/tree/main/docs/sesctl)

Camp setup guide: [hermes-agent.md — pluginctl workflow](../../../../hermes-agent.md#first-plugin-build-on-thor--use-pluginctl)

---

## What pluginctl is

`pluginctl` is the Sage command-line tool for **developing and testing edge plugins on a Waggle node**. It builds your Dockerfile into a container image, runs it inside the node's Kubernetes (WES/k3s) stack, and wires up the real upload path (RabbitMQ → Beehive) — without requiring ECR portal registration first.

```
  Your plugin repo (Dockerfile + app.py)
           │
           ▼
  sudo pluginctl build .     ──► container image (node-local registry or printed ref)
           │
           ▼
  sudo pluginctl run ...     ──► WES pod in default namespace
           │
           ▼
  plugin.publish / upload_file ──► Beehive (real data path)
```

**Contrast with `sesctl`:** the Edge Scheduler (`sesctl submit`) is the **production** path — it requires the plugin to be registered in ECR. Use `pluginctl` while iterating; move to `sesctl` when ready to schedule fleet jobs.

---

## Prerequisites (Thor)

```bash
which pluginctl
pluginctl -h
sudo pluginctl ps          # confirms k3s/WES is reachable
```

- **WES/k3s must be running** — `pluginctl` talks to the cluster via kubeconfig (default `/etc/rancher/k3s/k3s.yaml` on Thor).
- **`sudo` is required on Thor** for build, run, logs, ps, rm, and exec — the kubeconfig is root-owned and `pluginctl` targets the `default` namespace where normal user accounts lack pod-create RBAC.
- Sage policy: **do not run apps directly on the node host** — use containers via `pluginctl` (gives proper GPU/device access inside the pod).

---

## Camp workflow (hello world)

From inside your plugin directory (must contain a `Dockerfile`):

```bash
git clone <your-plugin-repo>
cd <plugin-dir>

# 1. Build
sudo pluginctl build .
# Prints image ref at the end, e.g.:
#   10.31.81.1:5000/local/my-plugin:latest
# or use: IMG=$(sudo pluginctl build .)

# 2. Run (one-shot — pod exits after plugin finishes)
sudo pluginctl run --name test-run <image-ref-from-build> -- <plugin-args>

# 3. Inspect
sudo pluginctl logs test-run
sudo pluginctl ps

# 4. Clean up before re-running same name
sudo pluginctl rm test-run
```

**Example** (from the upstream tutorial):

```bash
git clone https://github.com/waggle-sensor/plugin-hello-world.git
cd plugin-hello-world
sudo pluginctl build .
sudo pluginctl run --name builtplugin --selector node-role.kubernetes.io/master=true \
  10.31.81.1:5000/local/plugin-hello-world
sudo pluginctl logs builtplugin
sudo pluginctl rm builtplugin
```

---

## Command reference (common)

| Command | Purpose |
| --- | --- |
| `pluginctl build <dir>` | Build from Dockerfile in directory; print image ref |
| `pluginctl run -n <name> <image> [-- args]` | Run plugin pod |
| `pluginctl deploy -n <name> <image> [-- args]` | Deploy persistent / continuous pod |
| `pluginctl logs <name>` | Stream plugin logs |
| `pluginctl ps` | List plugin pods |
| `pluginctl rm <name>` | Remove plugin pod |
| `pluginctl exec <name> -- <cmd>` | Run command inside running pod |
| `pluginctl -h` | Full help |

Useful `run` / `deploy` flags:
- `-e KEY=VAL` / `--env-from <file>` — inject env (use for camera creds; never argv)
- `--selector resource.gpu=true` — GPU placement
- `-v HOST:CONTAINER` — volume mount (often needs a node selector on Thor)
- `--develop` — enable WAN access when needed

---

## Dockerfile requirements on Thor

Thor nodes alias `docker` to **Podman**. Two rules that bite newcomers:

1. **Fully-qualified base image** — Podman has no default unqualified registry:
   ```dockerfile
   FROM docker.io/waggle/plugin-base:1.1.1-base
   ```
   A bare `FROM waggle/plugin-base:...` fails with "did not resolve to an alias".

2. **ENTRYPOINT required** — missing `ENTRYPOINT`/`CMD` causes `pluginctl run` to fail silently or exit immediately.

Standard plugin layout:
```
app.py
Dockerfile
requirements.txt
sage.yaml          # ECR metadata (name, version) — for portal submission later
overview.md
```

---

## pluginctl vs podman vs Hermes terminal

| Tool | What it does |
| --- | --- |
| **`sudo pluginctl build`** | **Camp default** — builds plugin image and registers for k3s |
| **`sudo pluginctl run`** | Runs plugin in WES pod with upload plumbing |
| **`podman build`** | Lower-level; image not visible to k3s until `podman save \| sudo k3s ctr images import -` — use only for [ECR-bypass side-load](pluginctl-sideload-and-node-build.md) when portal builds fail |
| **Hermes `terminal.backend: docker`** | Hermes's own **tool sandbox** for shell commands — separate from plugin builds; camp profile uses `local` on Thor because Podman `--init` needs `catatonit` (exit 125) |

Do not confuse Hermes terminal sandbox issues with plugin development — plugins go through `pluginctl`.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `pods is forbidden` / cannot create in `default` | RBAC — user lacks pod-create in `default` | Prefix with `sudo` |
| `permission denied` on kubeconfig | k3s.yaml is root-only | `sudo pluginctl ...` |
| Build push to `10.31.81.1:5000` refused | Node-local registry unreachable (`lan0` down) | Push to Sage ECR ref and `pluginctl run` that ref, or side-load via `k3s ctr images import` — see `pluginctl-sideload-and-node-build.md` |
| `pluginctl run` same name fails | Old pod still exists | `sudo pluginctl rm <name>` first |
| `torch.cuda.is_available()` False on host | `/dev/nvmap` permissions (Tegra) | Run inside `pluginctl` pod, not host Python |
| ECR portal build fails (runc `/proc/acpi`) | Fleet-wide build regression | `podman build` + import + `pluginctl run` — see `ecr-build-proc-acpi-failure.md` |

---

## When to graduate from pluginctl

1. **pluginctl** — iterate on code, verify uploads hit Beehive, debug logs
2. **ECR registration** — register app + image in portal (when builds work or after side-load path)
3. **sesctl submit** — schedule recurring jobs on the fleet

---

## Deeper references in this skill

- `pluginctl-sideload-and-node-build.md` — side-load vs SES, registry workarounds, podman import
- `plugin-deploy-pluginctl-vs-ses.md` — deploy paths, credentials via Secret, podman quirks
- `direct-node-testing.md` — when k3s is down; fallbacks
- `docker-build-deploy.md` — Blackwell/Thor base images, ECR submission
- `deployment-and-diagnostics.md` — `default` vs `ses` namespace semantics
