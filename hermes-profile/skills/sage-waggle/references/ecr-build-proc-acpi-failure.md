# ECR build failure: every RUN step dies at runc init ("can't mask /proc/acpi")

Fleet-wide Sage ECR/Jenkins build regression (confirmed 2026-07, filed
waggle-edge-stack#110). Read this BEFORE trying to "fix" an ECR build that fails
on a RUN step — the fix is NOT in your plugin.

## Signature
```
buildctl --addr tcp://buildkitd:1234 build --frontend=dockerfile.v0 \
  --opt platform=linux/amd64,linux/arm64 ... --output type=image,...,push=true
...
#N [linux/arm64 2/5] RUN <anything: apt-get OR pip install>
#N 0.3xx runc run failed: unable to start container process: error during
  container init: can't mask dir "/proc/acpi": mount src=tmpfs, dst=/proc/acpi,
  flags=MS_RDONLY, data=nr_blocks=1,nr_inodes=1: invalid argument
error: failed to solve: process "/bin/sh -c ..." did not complete successfully: exit code: 1
```

## Root cause (do NOT waste a cycle on wrong hypotheses)
runc masked-paths hardening from CVE-2025-31133 / -52881 / -52565 (published
2025-11-05). The Sage `buildkitd` builder host was upgraded to a patched runc
(>= 1.2.8 / 1.3.3 / 1.4.0-rc.3) whose stricter `/proc/acpi` tmpfs mask now returns
`invalid argument` on that host's kernel — so EVERY exec/RUN container init fails.

Tell-tales that it's the BUILDER, not your plugin:
- FROM / WORKDIR / COPY all succeed; the FIRST `RUN` dies at container init.
- Arch-independent — both linux/arm64 AND linux/amd64 fail identically (NOT a QEMU
  issue; that's a separate problem).
- **Base-image-independent.** PROVEN: swapping `waggle/plugin-base:1.1.1-base` ->
  `python:3.12-slim` produced the IDENTICAL error on the pip RUN. Do not chase a
  base-image theory — it will cost you a release cycle for nothing.
- Regression proof: registering Sage's OWN unchanged `waggle-sensor/plugin-
  imagesampler` (built fine ~1yr ago) fails today on its first `RUN` (apt-get).

## What does NOT fix it (tried, confirmed useless)
- Changing the base image (any base fails).
- Slimming/reordering requirements, dropping `RUN` layers — `RUN pip install`
  cannot be dropped and still fails. (Dropping an unnecessary `apt-get` RUN is a
  fine cleanup but doesn't unblock; the next RUN fails identically.)

## Workaround (the only thing that works today)
Build natively on-node with podman (podman's RUN works), then side-load:
`podman build` -> `podman save | sudo k3s ctr images import -` -> `pluginctl deploy`.
See references/pluginctl-sideload-and-node-build.md.

## The fix is Sage-side (not ours)
Upgrade the builder host kernel, or pin/patch runc to a host-compatible combo, or
relax the buildkitd build-sandbox OCI masked-paths config for /proc/acpi. Track /
escalate via a GitHub issue on waggle-sensor/waggle-edge-stack. Existing ECR
images (yolo/birdnet/bioclip) only exist because they were built BEFORE the runc
upgrade; they'll hit the same wall on their next rebuild.
