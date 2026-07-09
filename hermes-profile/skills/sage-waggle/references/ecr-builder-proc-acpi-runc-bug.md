# ECR builder broken: every `RUN` fails at runc init (`/proc/acpi` masking)

**Status (2026-07):** P1, fleet-wide, BUILDER INFRASTRUCTURE — not fixable from any
plugin repo. Interim: build on-node with podman + `pluginctl` side-load.

## Symptom

The ECR portal "Register & Build" → Jenkins → buildkit pipeline fails EVERY plugin
whose Dockerfile has a `RUN` step (all of them — `RUN pip install` is universal).

```
buildctl --addr tcp://buildkitd:1234 build --frontend=dockerfile.v0 \
  --opt platform=linux/arm64,linux/amd64 ... --output type=image,...,push=true
...
#12 [linux/arm64 4/5] RUN pip install --no-cache-dir -r /app/requirements.txt
#12 0.348 runc run failed: unable to start container process: error during
  container init: can't mask dir "/proc/acpi": mount src=tmpfs, dst=/proc/acpi,
  flags=MS_RDONLY, data=nr_blocks=1,nr_inodes=1: invalid argument
error: failed to solve: ... exit code: 1
```

## Root cause (confirmed)

runc masked-paths hardening from **CVE-2025-31133 / CVE-2025-52881 /
CVE-2025-52565** (published 2025-11-05). Those patches changed how runc masks
directories like `/proc/acpi` (read-only tmpfs mounted over the path). The Sage
`buildkitd` builder host was upgraded to a patched runc (>= 1.2.8 / 1.3.3 /
1.4.0-rc.3); its stricter mask now returns `invalid argument` for `/proc/acpi` on
that host's kernel, failing every build-step container init.

Refs:
- https://github.com/opencontainers/runc/security/advisories/GHSA-9493-h29p-rfm2
- https://github.com/advisories/GHSA-9493-h29p-rfm2

## Why it is a BUILDER bug, not a plugin bug (diagnostic checklist)

- Base image pulls/extracts fine for BOTH linux/arm64 AND linux/amd64.
- FROM / WORKDIR / COPY all succeed (COPY shows CACHED).
- The FIRST `RUN` dies at container init; arch-independent (both platforms fail
  identically) → not QEMU/emulation.
- The `RUN` command never begins executing — it dies in init BEFORE pip/apt runs.

## Proven NOT a fix — do not repeat

- **Base swap does NOT help.** image-sampler2 v0.5.0 on
  `waggle/plugin-base:1.1.1-base` → `RUN pip3 install` failed with `/proc/acpi`.
  v0.5.1 swapped to `python:3.12-slim` (+ slimmed reqs) → FROM/WORKDIR/COPY
  succeeded, `RUN pip install` failed with the IDENTICAL error on both arches.
  (The base swap is still a net improvement to KEEP — modern Python 3.12, smaller
  image, no OpenCV/numpy chain — it just doesn't unblock ECR.)
- **requirements.txt / Dockerfile tweaks do NOT help** — the RUN never executes.

## WORKFLOW LESSON

Before diagnosing ANY Sage platform build/deploy failure, read
`~/AI-projects/Infra-problems-to-fix.md` FIRST. This exact bug was already logged
there as issue #2 (with root cause + fix options) BEFORE this session started.
Skipping it led to a base-image hypothesis and a wasted release cycle (0.5.0→0.5.1)
testing a fix that couldn't work. That doc is the running list of known platform
blockers; check it before forming theories.

## Regression-proof plugin for a bug report

`waggle-sensor/plugin-imagesampler` (the Sage-owned upstream image sampler that
image-sampler2 forks): 16 releases, latest v0.3.8 (Jan 22 2025), Docker Hub image
`waggle/plugin-imagesampler` last pushed ~1 year ago → it built via this same ECR
pipeline back then. Its Dockerfile has unchanged `RUN apt-get ...` and
`RUN pip3 install ...` steps. A rebuild today with zero source changes fails at the
first `RUN` with the identical `/proc/acpi` error → the plugin didn't change, the
builder did. Being Sage-owned, it can't be dismissed as "your custom plugin."
Caveat to state honestly in the issue: "built cleanly a year ago" is inferred from
the Docker Hub push date; for an airtight claim, re-trigger a `plugin-imagesampler`
rebuild in the portal and attach the failing log.

## Suggested fixes (Sage-side, any one unblocks)

1. Upgrade the buildkitd host kernel so `/proc/acpi` supports the tmpfs mask-mount
   the patched runc requires; OR
2. Pin/patch runc on the builder to a version compatible with the host kernel; OR
3. Relax the buildkitd build sandbox's OCI masked-paths config for `/proc/acpi`
   (build containers are ephemeral/trusted → lower risk than for runtime pods).

## Where to file the issue

`waggle-sensor` org. Best target: `waggle-sensor/sage-ecr` (the ECR build service)
if it exists/has Issues enabled; else `waggle-sensor/waggle-edge-stack` (WES infra).
