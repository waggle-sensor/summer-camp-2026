# Reviewing an external project for Sage edge-computing adaptation

Task class: Pete pulls an external repo into `~/AI-projects/<Name>` (often an
academic ML/CV pipeline: YOLO, SORT, thermal/audio, HPC/SLURM) and asks you to
"take a look." The real goal is almost always: assess it for adaptation to run on
a Sage node as a plugin. Deliverable pattern he then wants: write observations
into a file IN the repo (e.g. `REVIEW-NOTES.md`) that he can hand to the author.

## Workflow that worked (Bat-Counting-YOLOv11-SORT, 2026-07)

1. Read breadth-first: README, dependency/env manifest (pixi.toml/requirements),
   the entrypoint scripts, core src, and any config/orchestration (SLURM `.sh`,
   Makefile). Read sample data + expected-output files — they're your ground truth.
2. Produce a structured review with these sections (this is the shape Pete likes):
   - What it is (one paragraph: purpose + who authored it + the actual ask).
   - Pipeline flow (numbered, file-by-file).
   - What works / is good (be fair, not just critical).
   - Issues — real bugs / rough edges (concrete: file+line, why it breaks).
   - Issues — edge-computing mismatches (the substance; see checklist below).
   - Platform/run note for THIS box (aarch64 — see below).
   - Suggested starting order (numbered, with your lean).
   - Open questions for the author (pull-ready list at the bottom).
3. Save it as `REVIEW-NOTES.md` in the repo root. Write ONLY that file unless asked
   to change code. Include reviewer=Flint + date + "observations only, no code
   changed" header so the author knows nothing was touched.

## Edge-computing mismatch checklist (what to flag on any HPC/desktop → edge port)

- **Orchestration:** SLURM `sbatch`/array jobs, HPC cluster assumptions → a Sage
  node has no SLURM; it runs as a k3s/pluginctl container. The whole orchestration
  layer needs rethinking.
- **Per-frame / per-item compute cost:** large model input sizes (e.g. YOLO
  `imgsz=1280` every frame), heavy pre-processing (background subtraction that
  transcodes whole videos to disk first) → too heavy / too much I/O for constrained
  edge HW. Flag for profiling + lightening (smaller imgsz, skip transcode, decide
  if each stage earns its accuracy cost).
- **Writing bulky artifacts by default:** annotated videos, intermediate files →
  an edge node whose point is to transmit only results should not write video.
- **Dependency bloat:** deps pulled but unused in the runtime path (audit for a
  slim image). Note anything that won't have an aarch64 build.
- **Dev-host assumptions:** macOS/MPS fallbacks, `.DS_Store`, CRLF line endings in
  configs (break `read` in bash), Windows paths.
- **Target-HW ambiguity:** ask whether the edge target is Jetson-class ARM+CUDA or
  CPU-only — it changes everything downstream.

## PITFALL: this box is aarch64; many such projects pin linux-64 + CUDA
`pixi.toml`/conda envs commonly pin `platforms=["linux-64"]` + CUDA builds, which
won't resolve on this ARM host, and CUDA conda builds may lack aarch64. Don't
present that as a repo defect — note it as "getting it to run here is itself part
of the edge port (edge devices are usually ARM)" and ask the author if there's a
tested aarch64/Jetson env.

## Common real bugs to check for in handed-off research code
- Broken imports referencing renamed/moved modules (e.g. `from src.deletion import
  background_subtraction` when the file is `bg_subtract_new.py` / func is
  `background_subtract`). Training scripts often rot while inference path is kept.
- Malformed sample CSVs (trailing-comma header explosion) — data rows still
  readable, but note it needs cleanup before pandas.
- Sample input set vs. expected-output set not lining up (video P1.1.2 present but
  counts file lists P1.2.1) → "reproduce our numbers" won't be 1:1.
- Dead/unreachable debug code (e.g. `if fr == 0: raise` placed after `fr += 1`).

## The eventual port target (state it so the review points somewhere)
Wrap as a Sage plugin: pywaggle publishes the result metric (e.g. a nightly count)
with ROI/config as the single user knob, following existing Sage plugin patterns
(`pluginctl-sideload-and-node-build`, `pywaggle2-nodeinfo-gps-design`). Real end
goal is: node runs the model, transmits results — not raw video off-node.
