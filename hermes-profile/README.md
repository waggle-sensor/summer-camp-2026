# Sage Camp Hermes Profile

Hermes **profile distribution** for Sage Grande Summer Camp 2026 — edge computing, Waggle plugins, Thor + Ollama.

Install on your Thor following [hermes-agent.md — Step 3A](../hermes-agent.md#step-3a--install-sage-profile-recommended). Use `hermes profile install` on new machines and `hermes profile update sage` to pull changes — not `export`/`import` or `hermes backup`.

## What's inside

```text
hermes-profile/
├── distribution.yaml    # manifest (name: sage, version 1.1.0)
├── SOUL.md              # agent personality + Graphify-first discovery rules
├── AGENTS.md            # always-on: query graphify-out/ before grepping skills
├── config.yaml          # Ollama default + NRP provider pre-wired (minimax-m2)
├── mcp.json             # Sage + Milvus SDK helper enabled; GitHub + Hugging Face MCP listed (disabled until tokens)
├── graphify-baseline.tar.gz  # Prebuilt graph — unpack if present (skips multi-hour extract)
├── skills/graphify/     # Required Graphify skill (/graphify <profile>)
├── skills/sage-waggle/  # Sage/Waggle skill + doc indexes (Sage, Thor, DuckDB, …)
├── skills/hf-*/         # Vendored Hugging Face skills (hf-cli, Gradio, Spaces, …)
├── skills/huggingface-*/# More HF workflow skills
├── skills/jetson-*/     # Vendored NVIDIA skills (Jetson Thor device/BSP, …) + TAO/DeepStream/cuOpt/…
├── skills/_vendor/      # Upstream LICENSE + SOURCE pins (HF + NVIDIA + Graphify)
├── docs/                # pywaggle2 design docs + project status
├── .graphifyignore      # Exclude evals/fixtures from the graph
└── README.md
```

| Shipped (distribution-owned) | Never shipped (user-owned) |
| --- | --- |
| SOUL.md, AGENTS.md, config.yaml, skills/, docs/, mcp.json, graphify-baseline.tar.gz | `memories/`, `sessions/`, `auth.json`, `.env`, `.venv-graphify/`, `graphify-out/` |
| Updated via `hermes profile update sage` | Preserved across updates; refresh graph via `/graphify … --update` after skill/doc changes |

## Prerequisites

- Hermes Agent installed on your Thor ([Part 1, Step 2](../hermes-agent.md#step-2--install-hermes-cli)) — choose **Blank Slate**
- Ollama running on the Thor with at least one model (e.g. `gemma4:31b`) — also required to **build** the Graphify skills/docs graph
- Your own Linux account on the assigned Thor blade
- **Graphify** — required after profile install. Create/use **`.venv-graphify`** and `graphify-out/` under **`~/.hermes/profiles/sage`** (not the git clone). Unpack **`graphify-baseline.tar.gz`** if present, otherwise `/graphify ~/.hermes/profiles/sage`. Ongoing → skill **`graphify`**. Guide: `skills/sage-waggle/references/graphify-guide.md`

### Thor tips

- **First response slow?** Default `gemma4:31b` uses the full Ollama context (~262K) — first turn can take 3+ minutes. See [Step 4B — Cap Ollama context](../hermes-agent.md#step-4b--cap-ollama-context-recommended).
- **Terminal backend is `local` by design** on Thors — avoids Docker/Podman sandbox exit 125 (`catatonit` not installed). See [Troubleshooting (Thor)](../hermes-agent.md#troubleshooting-thor).
- **Build plugins with `sudo pluginctl build`** for on-node development — not raw `podman build` for first tests. See [pluginctl workflow](../hermes-agent.md#first-plugin-build-on-thor--use-pluginctl).

## Install

```bash
git clone https://github.com/waggle-sensor/summer-camp-2026.git
cd summer-camp-2026
hermes profile install ./hermes-profile --name sage --alias
hermes profile use sage
cp ~/.hermes/profiles/sage/.env.EXAMPLE ~/.hermes/profiles/sage/.env

# Required — Graphify (venv + optional baseline tarball; then skill graphify)
cd ~/.hermes/profiles/sage
if [ ! -x .venv-graphify/bin/python ]; then
  python3 -m venv .venv-graphify
  .venv-graphify/bin/pip install -U pip
  .venv-graphify/bin/pip install -U 'graphifyy[ollama]'
fi
if [ ! -f graphify-out/graph.json ] && [ -f graphify-baseline.tar.gz ]; then
  tar -xzf graphify-baseline.tar.gz
fi
test -f graphify-out/graph.json && echo "graph ok"
# If still missing: in Hermes run  /graphify ~/.hermes/profiles/sage
# After skill/doc changes:         /graphify ~/.hermes/profiles/sage --update
hermes profile info sage
hermes doctor
```

Launch with `sage` or `hermes -p sage`. The agent follows `AGENTS.md`: **query Graphify before grepping skills**.

### Optional env vars

| Variable | When needed |
| --- | --- |
| `NVIDIA_API_KEY` | Part 2 — NVIDIA Build inference ([hermes-agent.md](../hermes-agent.md#part-2-nvidia-hosted-apis)) |
| `NRP_LLM_API_KEY` | Part 2B — NRP Managed LLMs (`minimax-m2`) ([hermes-agent.md](../hermes-agent.md#part-2b-nrp-managed-llms)) |
| `SAGE_PORTAL_TOKEN` | Sage MCP job-submission tools only — read-only MCP works without it |
| `GITHUB_MCP_PAT` / `GITHUB_PERSONAL_ACCESS_TOKEN` | Optional GitHub MCP (`https://api.githubcopilot.com/mcp/`) — see `skills/sage-waggle/references/github-mcp-server.md` |
| `HF_TOKEN` / `HUGGINGFACE_HUB_TOKEN` | Optional Hugging Face MCP (`https://huggingface.co/mcp`) — see `skills/sage-waggle/references/huggingface-mcp-server.md` |

## Sage access setup

The skill knows *how* Sage works, but you need your own access to touch nodes and data:

1. **Sage portal account** — sign in at <https://portal.sagecontinuum.org> (Globus / institutional login).
2. **Portal access token** (for protected data downloads) — generate at <https://portal.sagecontinuum.org/account/access>. Keep in a file you control (e.g. `~/.sage/token.txt`) — never commit it.
3. **Node SSH access** — granted per-node by the instructor; ask for the exact `ssh` route and credentials.
4. **Sage MCP** — pre-wired in `mcp.json`. Read-only tools need no token. For job-submission tools, set `SAGE_PORTAL_TOKEN` in your profile `.env` with Bearer header configured post-install.
5. **GitHub MCP** (optional) — endpoint `https://api.githubcopilot.com/mcp/` ([registry](https://github.com/mcp/github/github-mcp-server)). In `mcp.json` as `github` with `enabled: false` until you add a PAT via `hermes mcp add` — details in `skills/sage-waggle/references/github-mcp-server.md`.
6. **Hugging Face MCP** (optional) — endpoint `https://huggingface.co/mcp` ([docs](https://huggingface.co/docs/hub/en/agents-mcp)). In `mcp.json` as `huggingface` with `enabled: false` until you add an HF token; configure tools at [settings/mcp](https://huggingface.co/settings/mcp) — details in `skills/sage-waggle/references/huggingface-mcp-server.md`.
7. **Hugging Face skills** — vendored from [huggingface/skills](https://github.com/huggingface/skills) into `skills/` (`hf-cli`, `huggingface-*`, `trl-training`, …). Start with `/skill hf-cli`. Full list: `skills/sage-waggle/references/huggingface-skills-index.md`.
8. **NVIDIA skills** — vendored from [NVIDIA/skills](https://github.com/NVIDIA/skills) (~230 skills: Jetson, DeepStream, TAO, cuOpt, NeMo, …). Discover via Graphify; Thor often uses `jetson-*`. Catalog: `skills/sage-waggle/references/nvidia-skills-index.md`. Docs: [docs.nvidia.com/skills](https://docs.nvidia.com/skills). Also `/skill nvidia-skill-finder`.
9. **Graphify (required)** — knowledge graph over `skills/` + `docs/` on the **installed** profile `~/.hermes/profiles/sage/` (not under the camp git clone). Bundled skill `skills/graphify/` + `AGENTS.md`. Ships `graphify-baseline.tar.gz`; create/use `.venv-graphify`, unpack the tarball if present, else `/graphify ~/.hermes/profiles/sage`. Ongoing → `/graphify ~/.hermes/profiles/sage --update`. Guide: `skills/sage-waggle/references/graphify-guide.md`. Upstream: [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify).
10. **Milvus SDK Code Helper** — `https://sdk.milvus.io/mcp/` ([docs](https://milvus.io/docs/milvus-sdk-helper-mcp.md)), pre-enabled as `sdk-code-helper`. Camp default runtime: **[Milvus Lite](https://milvus.io/docs/milvus_lite.md)** (local `.db`), not a full Milvus server. See `skills/sage-waggle/references/milvus-sdk-helper-mcp.md`.

See `skills/sage-waggle/references/mcp-tools.md` (Sage), `github-mcp-server.md` (GitHub), `huggingface-mcp-server.md` + `huggingface-skills-index.md` (Hugging Face), `nvidia-skills-index.md` (NVIDIA), `graphify-guide.md` (Graphify), and `milvus-sdk-helper-mcp.md` (Milvus).

## Verify (smoke test)

```bash
test -f ~/.hermes/profiles/sage/graphify-out/graph.json && echo "graph ok"
hermes skills list | grep -E 'graphify|sage-waggle|hf-cli|jetson-'
hermes mcp list                              # 'sage' should show connected
sage                                         # or: hermes -p sage
```

Ask: **"Using the graphify graph, which skill and references cover the Sage ECR /proc/acpi build failure and the workaround?"**

The agent should `graphify query` (or read `GRAPH_REPORT.md`), then land on **`sage-waggle`** / ECR refs — not invent answers by grepping randomly. If the graph is missing, unpack `graphify-baseline.tar.gz` under `~/.hermes/profiles/sage` or run `/graphify ~/.hermes/profiles/sage`. If the graph exists and skills/docs changed, use `/graphify ~/.hermes/profiles/sage --update`.

## Your first task (guided walkthrough)

Run these as prompts inside `hermes -p sage` (with the sage-waggle skill active):

1. **Orient.** *"Give me a 5-bullet overview of what a Sage/Waggle plugin is and the lifecycle from code to running on a node."*
2. **Explore live data (needs Sage MCP).** *"List a few available Sage nodes and show the latest temperature readings from one of them."*
3. **Read a real design.** *"Summarize `docs/pywaggle2-design.md` — specifically how a plugin should get its node's VSN and GPS location."*
4. **Build something small.** *"Help me scaffold a minimal plugin that captures one camera snapshot and prints its size — using placeholder camera credentials I'll fill in from my instructor."*
5. **Learn the pitfalls.** *"What are the top 5 mistakes people make deploying Sage plugins, from the sage-waggle skill?"*

## Use the skill

```bash
hermes -p sage -s sage-waggle
# or, inside a running session:
/skill sage-waggle
```

## Design docs

`docs/` are plain Markdown for context:

- `pywaggle2-design.md` — node identity, GPS resolution, camera acquisition
- `local-cache-design.md` — shared `/local-cache` design
- `project-status.txt` — current project status
- `Infra-problems-to-fix.md` — running infra issues list

## End of camp — contribute your brain

Before you leave, contribute what you learned back to this distribution so the shared Sage agent improves for everyone. See **[hermes-agent.md — End of camp](../hermes-agent.md#end-of-camp--contribute-your-brain-required)** for the full checklist.

## Updates

```bash
hermes profile update sage
cd ~/.hermes/profiles/sage
# After skill/doc updates with an existing graph:
# /graphify ~/.hermes/profiles/sage --update
# Start-from-scratch (rare): /graphify ~/.hermes/profiles/sage
# Instructor: refresh shipped baseline after rebuilding on the installed profile,
# then copy graphify-out/ into the distribution checkout before packing:
# tar -czf graphify-baseline.tar.gz graphify-out
```

Replaces distribution-owned files (SOUL, AGENTS, skills, mcp.json, docs). **Preserves** your `config.yaml` tweaks and all user data (memories, sessions, `.env`). Pass `--force-config` only to reset config to the distribution default. Refresh the **installed** profile graph with `/graphify ~/.hermes/profiles/sage --update` after updates (not the git clone).

## Author / versioning

- Manifest: `distribution.yaml` (`name: sage`, `version: 1.1.0`)
- Tag releases in git (`git tag v1.0.0`) for version tracking
- See the [Profile Distributions author guide](https://hermes-agent.nousresearch.com/docs/user-guide/profile-distributions#for-authors-publishing-a-distribution)

### Before camp — Thor fleet prep (optional)

| Action | Why |
| --- | --- |
| Pre-create `gemma4-64k` on each Thor | Students skip [Step 4B](../hermes-agent.md#step-4b--cap-ollama-context-recommended) |
| Ship `graphify-baseline.tar.gz` (students unpack + create `.venv-graphify`) | Warm graph in seconds (no multi-hour extract) |
| `apt install catatonit` | Enables Hermes Docker sandbox later |
| Pre-pull `docker.io/nikolaik/python-nodejs:python3.11-nodejs20` | Podman short-name fix |

### Reserved profile names

Do not use: `hermes`, `test`, `tmp`, `root`, `sudo`

---

*Everything here is knowledge, not secrets. Bring your own keys, node access, and credentials.*
