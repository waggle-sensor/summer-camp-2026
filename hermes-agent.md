# Hermes Agent Setup Guide
>NOTE: This is stil in development, so go ahead and try it out and let us know if you have any issues.

Run **Hermes Agent on your Thor** — your laptop is only an SSH client. Hermes handles files, terminal, and tools on the Thor; inference runs on the same machine via **Ollama** (Part 1) or over HTTPS to **NVIDIA Build** (Part 2).

Every participant has their **own Linux account** on the Thor. Hermes installs into your home directory (`~/.hermes/`) — agents are isolated by default. To share config or set up on a new machine, use a **profile distribution** ([Part 3](#part-3-transferring-the-brain)).

| Guide | Best for |
| ----- | -------- |
| [Part 1 — Thor + Ollama](#part-1-thor--ollama) | Local GPU inference via Ollama on your assigned Thor |
| [Part 2 — NVIDIA Hosted APIs](#part-2-nvidia-hosted-apis) | Cloud inference via NVIDIA Build (no Ollama needed) |
| [Part 3 — Transferring the brain](#part-3-transferring-the-brain) | Share agent config or move to a new machine via profile distribution |
| [Comparison](#thor-vs-nvidia-hosted-apis) | Choosing between the two inference approaches |
| [Switching between approaches](#switching-between-the-two-approaches) | Swap providers without reinstalling |

**Docs:** [Hermes Documentation](https://hermes-agent.nousresearch.com/docs/) · [Profile Distributions](https://hermes-agent.nousresearch.com/docs/user-guide/profile-distributions)

---

# Part 1: Thor + Ollama

Hermes and Ollama both run on the Thor. Your laptop connects via SSH and attaches to a tmux session.

## At a glance

```
  Laptop (SSH)                    Thor GPU
┌──────────────────┐              ┌──────────────────────────┐
│  Terminal only   │   SSH        │  Hermes Agent            │
│  tmux attach     │─────────────►│  Ollama (localhost:11434)│
│                  │              │  Files, terminal, tools  │
└──────────────────┘              └──────────────────────────┘
```

**Flow:** SSH to Thor → Install Hermes CLI → Install Sage profile → Verify Ollama → Run in tmux

---

## Prerequisites

- [ ] **Your personal Linux account** on the assigned Thor blade (provided by camp organizers)
- [ ] SSH access: `ssh your-linux-user@thor-host` (use the username you were assigned)
- [ ] Ollama installed and running on the Thor (shared system service — ask an instructor if it's not running)
- [ ] At least one model pulled on the Thor (e.g. `gemma4:31b`)
- [ ] Laptop with a terminal/SSH client only — nothing is installed locally

---

## Your account, your agent

You SSH in as **your own Linux user** (e.g. `ssh jsmith@thor-host`), not a shared account. Hermes installs entirely under your home directory — no root or sudo needed.

| Shared on Thor | Private to your Linux account |
| --- | --- |
| Ollama + GPU inference | `~/.hermes/` (agent brain) |
| System packages (tmux, etc.) | tmux sessions (Linux isolates per user) |
| Thor hostname / SSH access | API keys in `~/.hermes/.env` |

- `~/.hermes/` — config, memories, skills, sessions
- `~/.local/bin/hermes` — CLI binary
- Other participants on the same Thor have their own `~/.hermes/` — you cannot see or overwrite each other's agents
- **Ollama is shared** (system-level); each user's Hermes connects to the same `localhost:11434`

---

## Step 1 — SSH into your Thor

```bash
ssh your-linux-user@thor-host
```

Replace `your-linux-user` with the Linux username you were assigned and `thor-host` with your blade hostname.

---

## Step 2 — Install Hermes CLI

Install the Hermes CLI into your home directory. Choose **Blank Slate** so the camp profile (Step 3A) provides the configuration.

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

| Choice | Select |
| ------ | ------ |
| Setup mode | **3. Blank Slate** — skip the wizard; profile install handles config |
| provider | **34. Leave unchanged** |
| Terminal backend | **Keep current (local)** |
| Your minimal agent is ready. What next? | **Start with everything disabled — finish now (most minimal)** |

Reload your shell and verify:

```bash
source ~/.bashrc   # or ~/.zshrc
hermes --version
```

---

## Step 3A — Install Sage profile (recommended)

> **Recommended.** Use this path unless profile install fails or you need a fully custom configuration.

The camp maintains a Hermes **profile distribution** in this repo at [`hermes-profile/`](hermes-profile/). It ships pre-configured SOUL, model settings, tools, and skills. See the [Profile Distributions guide](https://hermes-agent.nousresearch.com/docs/user-guide/profile-distributions) for details.

**What the distribution ships vs. what stays private:**

| Shipped (distribution-owned) | Never shipped (user-owned) |
| --- | --- |
| SOUL.md, config.yaml, skills/, mcp.json, cron/ | `memories/`, `sessions/`, `auth.json`, `.env` |
| Updated via `hermes profile update` | Preserved across updates — your brain stays isolated |

### Install from local clone (recommended)

`hermes profile install github.com/org/repo` clones the **repo root** as the distribution — it does not support subpaths. Since the profile lives inside this monorepo, clone first:

```bash
git clone https://github.com/FranciscoLozCoding/summer-camp-2026.git
#git checkout <branch> #if desired
cd summer-camp-2026
hermes profile install ./hermes-profile --name sage --alias
```

### Install from standalone git repo (alternative)

If `hermes-profile/` is published as its own repository:

```bash
hermes profile install github.com/FranciscoLozCoding/sage-hermes --alias
```

### What happens on install

1. Copies distribution files into `~/.hermes/profiles/sage/`
2. Shows manifest preview (name, version, required env vars)
3. Marks each `env_requires` key as `✓ set` or `needs setting`
4. Prompts for confirmation (pass `-y` to skip)
5. Writes `.env.EXAMPLE` — you copy to `.env`
6. With `--alias`, creates a `sage` wrapper command

### Post-install

```bash
hermes profile use sage
cp ~/.hermes/profiles/sage/.env.EXAMPLE ~/.hermes/profiles/sage/.env
# Edit .env if needed — add NVIDIA_API_KEY (nvapi-...) for Part 2; leave blank for Thor+Ollama
hermes profile info sage
hermes doctor
```

Launch with `sage` or `hermes -p sage`.

### Pull camp config updates

```bash
hermes profile update sage
```

Replaces distribution-owned files (SOUL, skills, cron, mcp.json). **Preserves** your `config.yaml` tweaks and all user data (memories, sessions, `.env`). Pass `--force-config` only to reset config to the distribution default.

> **Security:** SOUL.md and skills are active on first chat. Cron jobs from the distribution are **not** auto-scheduled — run `hermes -p sage cron list` and enable explicitly.

---

## Step 3B — Manual setup (backup)

<details>
<summary><strong>Backup — manual interactive setup</strong> (use only if profile install fails or you need custom config)</summary>

Run the full installer wizard instead of the camp profile:

```bash
hermes setup
```

Work through the installer in this order. Values marked *example* depend on your Thor model.

### Setup mode

| Choice | Select |
| ------ | ------ |
| Setup mode | **2. Full setup** — configure providers and tools yourself |

### Model provider

| Field | Value |
| ----- | ----- |
| Provider | **Custom / OpenAI-compatible** (`custom` direct API) |
| API base URL | `http://127.0.0.1:11434/v1` |
| API key | Leave blank |
| Compatibility mode | **1. Auto-detect** |

> **Why `127.0.0.1`?** Hermes and Ollama run on the same Thor — no SSH tunnel needed.

### Model settings (*example*)

| Field | Example value | Notes |
| ----- | ------------- | ----- |
| Model name | `gemma4:31b` | Must match a model on the Thor |
| Context length | `256000` | Match your model's limit |
| Display name | `sage-thor-H020-gemma4-31b` | Any label that helps you identify this endpoint |

### Terminal & platforms

| Prompt | Select |
| ------ | ------ |
| Terminal backend | **Keep current (local)** — tools run on the Thor filesystem |
| Platforms (Mattermost, Slack, etc.) | Skip — press **Enter** |

### CLI tools

Enable these tools (toggle with **Space**, confirm with **Enter**):

| Enabled | Tool |
| ------- | ---- |
| ✓ | Web Search & Scraping |
| ✓ | Browser Automation |
| ✓ | Terminal & Processes |
| ✓ | File Operations |
| ✓ | Code Execution |
| ✓ | Vision / Image Analysis |
| ✓ | Text-to-Speech |
| ✓ | Skills |
| ✓ | Task Planning |
| ✓ | Memory |
| ✓ | Session Search |
| ✓ | Clarifying Questions |
| ✓ | Task Delegation |
| ✓ | Cron Jobs |
| ✓ | Computer Use |

Leave video generation, image generation, and integrations you don't need unchecked.

### Provider choices

| Category | Select |
| -------- | ------ |
| Browser | **Local Browser** (recommended, free) |
| Text-to-Speech | **Microsoft Edge TTS** (free) |
| Web Search | **DuckDuckGo (ddgs)** (free, no API key) |

### Finish install

Reload your shell and verify:

```bash
source ~/.bashrc
hermes --version
```

**Full installer prompts (reference):**

```
(○) 1. Quick Setup (Nous Portal)
(●) 2. Full setup
(○) 3. Blank Slate

API base URL: http://127.0.0.1:11434/v1
API key: <leave blank>
Choice [1-4]: 1   # Auto-detect

Model name: gemma4:31b
Context length: 256000
Display name: sage-thor-H020-gemma4-31b
```

> **Note:** Browser automation on a headless Thor may need extra setup (local browser vs. MCP). This is optional — not required for core agent use.

</details>

---

## Step 4 — Verify Ollama on the Thor

Run these on the Thor (in your SSH session):

**List models:**

```bash
curl http://127.0.0.1:11434/api/tags
```

**Verify the OpenAI-compatible endpoint:**

```bash
curl http://127.0.0.1:11434/v1/models
```

If both return model data, Hermes can connect.

---

## Step 5 — Run Hermes in tmux

tmux keeps Hermes running after you close your laptop or drop SSH.

**Check tmux is available** (should be pre-installed):

```bash
tmux -V
```

> If tmux is missing, ask an instructor. Participants typically have no sudo. Each user's tmux sessions are isolated by Linux — you don't need a unique session name to avoid collisions with other participants.

**Start and detach:**

```bash
tmux new -s hermes
# Inside the session:
sage          # or: hermes -p sage   (if you used profile install)
# or: hermes       (if you used manual setup)

# Detach: Ctrl-b then d
# Reattach from any SSH session:
tmux attach -t hermes

# List sessions:
tmux ls
```

**Optional detached start:**

```bash
tmux new -s hermes -d 'sage'
tmux attach -t hermes
```

### Tmux scrollback (save session transcripts)

Long Hermes sessions can scroll past the default buffer. Increase scrollback once on the Thor:

```bash
echo 'set-option -g history-limit 50000' >> ~/.tmux.conf
# Restart tmux server or start a new session for the setting to take effect
```

**Save a full session transcript** — from **inside** the `hermes` tmux session (after `tmux attach -t hermes`):

```bash
chmod +x ~/summer-camp-2026/scripts/write-tmux.sh   # once
~/summer-camp-2026/scripts/write-tmux.sh
```

The script captures the full scrollback (with ANSI colors) to `~/AI-projects/tmux-logs/transcript_<timestamp>.ansi`. View with:

```bash
less -R ~/AI-projects/tmux-logs/transcript_*.ansi
```

---

## Step 6 — Reconfigure later (optional)

```bash
hermes model              # add or change model providers
hermes setup              # re-run setup wizard
hermes profile update sage   # pull camp profile updates
```

---

## Troubleshooting (Thor)

| Check | Command |
| ----- | ------- |
| Ollama running? | `curl http://127.0.0.1:11434/api/tags` |
| OpenAI endpoint? | `curl http://127.0.0.1:11434/v1/models` |
| Hermes health | `hermes doctor` |
| Reattach agent | `tmux attach -t hermes` |

**If Hermes can't connect:**

1. Confirm Ollama is running on the Thor (ask an instructor).
2. Confirm the model name in Hermes matches a model from `/v1/models`.
3. Run `hermes doctor` and check your profile config.

**tmux issues:**

- Thor rebooted → SSH back in and `tmux new -s hermes`
- Closed laptop → `tmux attach -t hermes` (agent keeps running on Thor)
- Can't see another user's session → expected; tmux sessions are per Linux account

To enable more tools later: `hermes setup tools` or edit `~/.hermes/.env`.

---

# Part 2: NVIDIA Hosted APIs

Hermes runs on the Thor and talks to **NVIDIA Build** over HTTPS. No Ollama required.

## At a glance

```
  Laptop (SSH)              Thor                    NVIDIA Build
┌──────────────┐     ┌──────────────────┐        ┌──────────────────────────┐
│  tmux attach │ SSH │  Hermes Agent    │  HTTPS │  integrate.api.nvidia    │
│              │────►│  (your account)  │───────►│  Managed GPU inference   │
└──────────────┘     └──────────────────┘  TLS   └──────────────────────────┘
```

No SSH tunnel. No Ollama. No local GPU to manage.

---

## Prerequisites

- [ ] SSH access to your Thor with Hermes installed ([Part 1](#part-1-thor--ollama))
- [ ] NVIDIA Developer account
- [ ] API key from [NVIDIA Build](https://build.nvidia.com/settings/api-keys)

If you used the camp profile (Step 3A), it may already define the NVIDIA provider — you only need to add your API key to `.env`.

---

## Step 1 — Create an account

Sign in or register at **[NVIDIA Build](https://build.nvidia.com/)**.

---

## Step 2 — Generate an API key

1. Go to **[API Keys](https://build.nvidia.com/settings/api-keys)**
2. Click **Get API Key**
3. Save the key — it looks like:

```text
nvapi-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Store it in **your** `~/.hermes/profiles/sage/.env` (or `~/.hermes/.env` for manual setup). API keys are never shared across Linux accounts.

---

## Step 3 — Choose a model

Browse the **[NVIDIA Model Catalog](https://build.nvidia.com/explore/discover)** and copy the exact model ID.

Popular options:

| Model ID |
| -------- |
| `meta/llama-3.3-70b-instruct` |
| `qwen/qwen3-235b-a22b` |
| `deepseek-ai/deepseek-r1` |
| `mistralai/mistral-large` |
| `nvidia/nemotron-3-ultra-550b-a55b` |

> Catalog IDs change over time — always copy from the catalog page.

---

## Step 4 — Configure Hermes

```bash
hermes model
```

| Setting | Value |
| ------- | ----- |
| Provider | **NVIDIA NIM** (build.nvidia.com or local NIM) |
| API Key | `nvapi-...` |
| Base URL | `https://integrate.api.nvidia.com/v1` |
| Model | Your catalog model ID |

Or add the key directly to `.env`:

```bash
# ~/.hermes/profiles/sage/.env
NVIDIA_API_KEY=nvapi-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

---

## Step 5 — Launch Hermes

```bash
tmux attach -t hermes    # if already running
# or start fresh:
tmux new -s hermes
sage                # or: hermes
```

All inference requests go to NVIDIA's hosted infrastructure from the Thor.

---

## Troubleshooting (NVIDIA)

1. API key must start with `nvapi-`.
2. Base URL must be exactly `https://integrate.api.nvidia.com/v1`.
3. Model ID must match the catalog exactly.
4. On the free tier, high demand can cause occasional delays.
5. Confirm the key is in **your** `.env`, not another user's.

**References:** [NVIDIA NIM API](https://build.nvidia.com/) · [API Reference](https://docs.nvidia.com/nim/large-language-models/latest/api-reference.html) · [Forum — connection issues](https://forums.developer.nvidia.com/t/not-connect-to-endpoint-https-integrate-api-nvidia-com-v1/324036)

---

# Part 3: Transferring the brain

Move agent configuration between machines or share it with your team via **profile distributions**. Use `export`/`import` only for local backup on the same machine.

## Mechanisms

| Mechanism | Purpose | Memories/sessions? | Credentials? |
| --- | --- | --- | --- |
| **`hermes profile install` / `update`** (distribution) | Team sharing, new Thor, or new machine — install config from git | No | No — each user fills `.env` |
| **`hermes profile export` / `import`** | Back up or restore a profile **on the same machine** | Yes | No (stripped) |

> **Team sharing and new machines:** Use a profile distribution — push config to git, then run `hermes profile install` or `hermes profile update` on each machine. Do **not** use `export`/`import` for handoffs between people or machines.
>
> **Personal memories and sessions are never shared** via distributions. Each Linux account keeps its own brain even when everyone installs the same profile.

**References:** [Hermes Memory](https://hermes-agent.nousresearch.com/docs/user-guide/features/memory) · [Profile Commands](https://hermes-agent.nousresearch.com/docs/reference/profile-commands) · [Profile Distributions](https://hermes-agent.nousresearch.com/docs/user-guide/profile-distributions)

## What makes up the brain

| Component | Location | What it carries |
| --- | --- | --- |
| Personality | `SOUL.md` | Agent instructions and tone |
| Memories | `memories/MEMORY.md`, `USER.md` | Facts and user preferences |
| Skills | `skills/` | Reusable procedures |
| Sessions | `state.db` | Conversation history (searchable) |
| Config | `config.yaml` | Model, tools, settings |

## Profile distribution (team sharing and new machines)

Use this when you want the **same agent configuration** — SOUL, skills, model settings, tools — on multiple machines or Thor blades. Works for teammates, moving to a new Thor, or syncing your agent across machines you own.

### Install on a new machine

SSH into the new Thor as your Linux user, install the Hermes CLI ([Part 1, Step 2](#step-2--install-hermes-cli)), then install the profile:

```bash
# From the camp repo
git clone https://github.com/FranciscoLozCoding/summer-camp-2026.git
cd summer-camp-2026
hermes profile install ./hermes-profile --name sage --alias

# Or directly from git (standalone profile repo)
hermes profile install github.com/FranciscoLozCoding/<profile-repo> --name sage --alias
```

Fill in your credentials and verify:

```bash
hermes profile use sage
cp ~/.hermes/profiles/sage/.env.EXAMPLE ~/.hermes/profiles/sage/.env
# Edit .env — add your API keys
hermes profile info sage
hermes doctor
```

Memories and sessions from your old machine **do not transfer** — each machine builds its own. Your agent config (SOUL, skills, tools) is what syncs via git.

### Pull updates (teammates or additional machines)

```bash
hermes profile update sage
```

Updates replace distribution-owned files (SOUL, skills, cron) but **never** touch `memories/`, `sessions/`, or `.env`.

### Publish changes (authors)

Camp organizers and team leads publish via git — see [Profile Distributions: For authors](https://hermes-agent.nousresearch.com/docs/user-guide/profile-distributions#for-authors-publishing-a-distribution) and the checklist in [`hermes-profile/README.md`](hermes-profile/README.md).

```bash
# After editing SOUL.md, skills/, config.yaml, etc. in the profile repo:
git add distribution.yaml SOUL.md skills/ config.yaml
git commit -m "v1.1.0: updated camp SOUL and skills"
git tag v1.1.0
git push --tags
```

Anyone with the profile installed runs `hermes profile update sage` to pick up the changes.

## End of camp — contribute your brain (required)

> **Don't forget:** Before you leave camp, contribute what you learned back to the shared Sage agent.

All week you build a personal **brain** under `~/.hermes/profiles/sage/` — memories, skill tweaks, reference notes, debugging recipes. That knowledge stays on your Thor unless you contribute it. Camp organizers merge student contributions into [`hermes-profile/`](hermes-profile/) so everyone can run `hermes profile update sage` and inherit the improvements.

### How to contribute

1. **Review your brain** on the Thor:

```bash
ls ~/.hermes/profiles/sage/memories/
ls ~/.hermes/profiles/sage/skills/
cat ~/.hermes/profiles/sage/memories/MEMORY.md   # if you wrote memories
```

2. **Export your brain** to a tarball:

```bash
hermes profile export sage -o ~/sage-brain-export.tar.gz
```

3. **Transfer the tarball** to an instructor — never post it in public channels.

4. **Instructors will extract shareable knowledge** and open PRs on your behalf.

## Same-machine backup (profile export/import)

Use `export`/`import` to snapshot or restore a profile **on your own machine** — for example before a risky config change, or to duplicate a profile under a new name. This is **not** the recommended way to share with teammates.

**Export:**

```bash
hermes profile list
hermes profile export sage -o ~/sage-backup.tar.gz
```

**Restore on the same machine:**

```bash
hermes profile import ~/sage-backup.tar.gz --name sage-restored
hermes profile use sage-restored
hermes doctor
```

**After import:**

- Reconfigure API keys in `.env` if needed (credentials are not included in exports)
- Run `hermes doctor`

## Comparison

| | `profile install` / `update` | `profile export` / `import` |
| --- | --- | --- |
| Use case | Team sharing, new Thor, new machine | Local backup (same machine only) |
| Share with teammates or other machines? | **Yes** (via git) | No |
| Scope | Distribution config (SOUL, skills, tools) | One profile + memories/sessions |
| Credentials | No — each user fills `.env` | Stripped |
| Format | git / local dir | `.tar.gz` |

---

# Thor vs. NVIDIA Hosted APIs

| | Thor + Ollama | NVIDIA Hosted APIs |
| --- | --- | --- |
| **Where Hermes runs** | Thor | Thor |
| **Where inference runs** | Thor (Ollama, local GPU) | NVIDIA Build (cloud) |
| **Laptop role** | SSH client + tmux attach | SSH client + tmux attach |
| **SSH tunnel** | Not needed | Not needed |
| **API key** | Not required | Required (`nvapi-...`) |
| **Internet** | Only for SSH | Always (on Thor) |
| **Models** | Any Ollama model on the Thor | NVIDIA catalog only |
| **Cost** | Shared Thor GPU | NVIDIA Build credits |

**Choose Thor + Ollama** when you want full model control on local GPU hardware.

**Choose NVIDIA** when you want cloud inference without managing Ollama or local models.

---

# Switching between the two approaches

Both providers are configured on the Thor. Switch anytime:

```bash
hermes model
```

Select the appropriate provider:

- **NVIDIA NIM** — for NVIDIA Hosted APIs
- **sage-thor-H020-gemma4-31b** (or your Thor display name) — for Thor + Ollama
- **sage** profile — if the camp profile defines both and you switch within it

If using the camp profile, you can also edit `~/.hermes/profiles/sage/.env` and `config.yaml` directly.
