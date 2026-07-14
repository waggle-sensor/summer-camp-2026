# Hermes setup
_Exported on 7/14/2026 at 12:47:21 CST from Cursor (3.11.19)_

---

**User**

continued working on Hermes setup documentation with Thor devkits and Nvidia hosted inference APIs @hermes-agent.md 
	- [ ] change the setup guide to install hermes on the Thor instead of the laptop. This means the Thor will not only be the inference server but the host of the agent as well
		- [ ] Also give directions to install and use tmux so the agent can run the background
		- [ ] make sure the instructions installs hermes in the userspace so each user has its own agent
	- [ ] Look into how to "transfer the brain" of hermes so we can share agents with each other
		- [ ] Also include those instructions in the setup doc

---

**Cursor**

Reviewing the Hermes setup doc and codebase to plan Thor-based installation, tmux, userspace setup, and agent brain transfer.


Searching Hermes docs for brain transfer, userspace install, and Thor-specific details.


Checking for Thor/Sage SSH access details in the repo or related docs.


**Thor access details**

> **How should participants SSH into their assigned Thor blade? (README still has TBD for H020–H023 access.)**
> - Via Sage SSH (e.g. ssh waggle-dev-node-...) — I'll provide exact hostnames later
> - Direct SSH to Thor hostnames (e.g. thor-h020.example) — I'll provide hostnames/credentials
> - Use placeholder hostnames in the doc for now (username@thor-host) ✔

Creating the plan from the current doc and Hermes official transfer commands.


---

**User**

keep in mind everyone will have their own linux account in the thors

---

**Cursor**

Updating the plan to reflect per-user Linux accounts on each Thor.


Updated the plan to reflect **per-participant Linux accounts** on each Thor. Main additions:

**Account model**
- SSH as your assigned Linux user (e.g. `jsmith@thor-host`), not a shared account
- Hermes lives entirely in your home dir (`~/.hermes/`, `~/.local/bin/hermes`) — no sudo
- Agents are isolated by default; sharing is only via export/import

**Shared vs. private table** (to go in the doc)

| Shared on Thor | Private to your account |
|---|---|
| Ollama + GPU | `~/.hermes/` (brain) |
| System packages (tmux) | tmux sessions |
| SSH hostname | API keys in `.env` |

**Other adjustments**
- Architecture diagram shows multiple users on one Thor sharing Ollama
- tmux: no `apt install` — assume pre-installed; Linux isolates sessions per user (no need for unique session names across participants)
- Brain transfer: `scp` between Linux accounts (same Thor or different)
- Removed all sudo instructions from the plan

Say the word when you want this implemented in `hermes-agent.md`.

---

**User**

Also use hermes profiles to share config, so add another method to set up Hermes agents using hermes profile. Mark this as recommended method, but keep the manual method as well as a backup. I will upload the hermes profile config to this repo

---

**Cursor**

Updating the plan to add a recommended `hermes profile` install path from a repo-hosted camp profile, with the manual setup kept as backup.


Updating the plan to add the recommended `hermes profile install` path from a repo-hosted camp profile.


Updated the plan with a **recommended profile-install path** and kept manual setup as backup. Summary:

**Two setup paths in Part 1**

| Method | Label | Flow |
|--------|-------|------|
| **3A — Recommended** | Camp profile from repo | `curl` install (Blank Slate) → `hermes profile install ./hermes-profile` → fill `.env` |
| **3B — Backup** | Manual wizard | Current full `hermes setup` walkthrough in a collapsible/secondary section |

**Repo addition (you'll upload)**
- New directory: `hermes-profile/` with `distribution.yaml`, `SOUL.md`, `config.yaml`, `skills/`, etc.
- Doc will reference install via local clone or git URL once the profile is in the repo

**Three concepts separated in "Transferring the brain"**
1. **Camp profile install** — shared starting config for everyone
2. **Profile export/import** — share a trained agent (memories, sessions)
3. **Full backup** — move entire install between machines

**New todos added**
- `profile-install-recommended` — Step 3A content
- `manual-setup-backup` — move wizard to Step 3B
- `profile-repo-placeholder` — wire real paths after you upload the profile

**Open item:** Confirm whether `hermes profile install github.com/org/summer-camp-2026/hermes-profile` works for a subdirectory, or if the profile needs its own repo — we'll test when implementing.

Upload the profile config when ready, or say the word to implement the doc changes.

---

**User**

https://hermes-agent.nousresearch.com/docs/user-guide/profile-distributions 

---

**Cursor**

Reviewing the uploaded profile-distributions reference and aligning the plan with the official docs.


Updating the plan with accurate details from the official Profile Distributions docs—especially install paths and author requirements.


Updated the plan using the [Profile Distributions](https://hermes-agent.nousresearch.com/docs/user-guide/profile-distributions) docs you shared. Main corrections:

**Install path (important fix)**
- `hermes profile install github.com/org/repo` clones the **repo root** only — no subpath support for `.../hermes-profile`
- **Recommended for this monorepo:** clone the camp repo, then:
  ```bash
  hermes profile install ./hermes-profile --name sage-camp --alias
  ```
- Standalone git install only works if `hermes-profile/` is its own repo

**Official installer behavior** (now in Step 3A)
- Manifest preview + env var check (`✓ set` / `needs setting`)
- `.env.EXAMPLE` generated on install
- `--alias` creates `sage-camp` wrapper
- `hermes profile update` replaces SOUL/skills but **preserves** memories, sessions, and `.env`
- Cron jobs are **not** auto-scheduled — user enables via `hermes -p sage-camp cron list`

**Author checklist** (for when you upload `hermes-profile/`)
- `distribution.yaml` + `.gitignore` before first commit
- Never commit `.env`, `auth.json`, `memories/`, `sessions/`
- Tag releases; note version pinning via `#v1.0.0` is planned but not yet available

**Three mechanisms clarified** (per official "when to use" guidance)

| Mechanism | Memories? | Credentials? |
|-----------|-----------|--------------|
| `profile install` | No | No — each user fills `.env` |
| `profile export/import` | Yes | Stripped |
| `hermes backup/import` | Yes | Included |

Ready to implement when you upload the profile config or give the go-ahead.

---

**User**

Implement the plan as specified, it is attached for your reference. Do NOT edit the plan file itself.

To-do's from the plan have already been created. Do not create them again. Mark them as in_progress as you work, starting with the first one. Don't stop until you have completed all the to-dos.

---

**Cursor**

Implementing the Hermes on Thor documentation plan. Reading the current file and starting the rewrite.


Writing the complete updated `hermes-agent.md` per the plan.


Adding the `hermes-profile/` placeholder with the author checklist from the plan.


All plan items are done. Summary of changes:

### [`hermes-agent.md`](hermes-agent.md) — full rewrite

**Architecture:** Hermes runs on the Thor (per Linux account); laptop is SSH + tmux only. SSH tunnel removed.

**Part 1 — Thor + Ollama**
- Prerequisites: personal Linux account, shared Ollama
- "Your account, your agent" table (shared vs. private)
- Step 1: SSH to Thor
- Step 2: Hermes CLI install (Blank Slate)
- **Step 3A (recommended):** `hermes profile install ./hermes-profile` from cloned repo
- **Step 3B (backup):** Manual wizard in a collapsible `<details>` block
- Step 4: Verify Ollama locally
- Step 5: tmux workflow (attach/detach/reattach)
- Step 6: Reconfigure / profile update
- Updated troubleshooting (no tunnel checks)

**Part 2 — NVIDIA Hosted APIs**
- Hermes on Thor → NVIDIA Build over HTTPS
- API keys in each user's own `.env`

**Part 3 — Transferring the brain**
- Three mechanisms: `profile install`, `export`/`import`, `backup`/`import`
- Step-by-step share workflow with `scp`
- Four-way comparison table

**Comparison & switching** updated for Thor-hosted model

### [`hermes-profile/README.md`](hermes-profile/README.md) — placeholder

- Expected distribution layout
- Author checklist and `.gitignore` template for when you upload the profile config

**Next step for you:** Add `distribution.yaml`, `SOUL.md`, `config.yaml`, and `skills/` under `hermes-profile/`, then replace `<org>` in the clone URL in the doc with your real GitHub org.

---

**User**

change the hermes profile name to be sage instead of sage-camp

---

**Cursor**

Renaming the profile from `sage-camp` to `sage` across the docs.


Renamed the profile from `sage-camp` to `sage` throughout [`hermes-agent.md`](hermes-agent.md) — 21 occurrences updated, including:

- Install command: `--name sage`
- Profile paths: `~/.hermes/profiles/sage/`
- CLI alias: `sage` / `hermes -p sage`
- All `profile use`, `update`, `export`, and tmux launch examples

The standalone git repo example is now `sage-hermes` (was `sage-camp-hermes`). Manual setup display names like `sage-thor-H020-gemma4-31b` are unchanged.

---

**User**

lets make sure we don't recommend hermes profile export/import when sharing with teamates but rather hermes profile distribution. hermes profile export/import are for backups on the same machine

---

**Cursor**

Updating the brain-transfer section to recommend profile distributions for team sharing and reserve export/import for same-machine backups.


Updated Part 3 to match the intended sharing model:

**Share with teammates → profile distribution**
- `hermes profile install` / `hermes profile update` via git
- New sections for teammates (install/update) and authors (publish via git)
- Explicit note: memories and sessions are never shared via distributions

**Same-machine only → profile export/import**
- Renamed section to "Same-machine backup"
- Removed all `scp` teammate transfer examples
- Use cases: snapshot before risky changes, restore or duplicate on the same machine

**Comparison table** now includes a "Share with teammates?" row — only `profile install` is Yes.

Also updated the intro, TOC, and [`hermes-profile/README.md`](hermes-profile/README.md) to match.

---

**User**

full machine migration also use git profile distribution 

---

**Cursor**

Updating Part 3 so new-machine setup uses profile distribution instead of `hermes backup`/`import`.


Updated Part 3 so **profile distribution** is the path for team sharing and new-machine setup:

**Removed:** `hermes backup` / `hermes import` section and comparison column

**Profile distribution now covers:**
- Team sharing
- Moving to a new Thor or machine (`hermes profile install` + fill `.env`)
- Pulling updates (`hermes profile update sage`)

**`export`/`import` only for:** same-machine local backup (unchanged)

**Comparison table** is now two columns: distribution vs. local export/import

Also noted that memories/sessions do not transfer across machines — only config (SOUL, skills, tools) syncs via git.

---

**User**

I have draft files that have the data needed for the profile distribution in @temp/ use that to complete @hermes-profile/ so it works with hermes profile distribution

here is the hermes docs again 
https://hermes-agent.nousresearch.com/docs/user-guide/profile-distributions 

---

**Cursor**

Reviewing the draft files in `temp/` and the current `hermes-profile/` layout against the profile distribution requirements.


Checking for credentials in the temp skill bundle and confirming the repo's GitHub org for the distribution source field.


I have enough context. `temp/` has the skill bundle and docs but is missing the distribution manifest files — those need to be created.


**Profile distribution scope**

> **Should `temp/docs/` (pywaggle2-design.md, local-cache-design.md, etc.) be copied into `hermes-profile/docs/` as part of the distribution?**
> - Yes — include docs/ in the profile (agent can reference them on Thor) ✔
> - No — skills/sage-waggle references are enough; skip docs/

---

**User**

update the plan to just use @temp/MEMORY.starter.md to be able to build the profile but dont copy it into the profile

---

**Cursor**

Updated the plan:

**`temp/MEMORY.starter.md`**
- **Reference only** when writing `SOUL.md` — embed condensed domain facts (pod identity, ECR runc workaround, BirdNET gain, Reolink auth, etc.)
- **Not copied** into `hermes-profile/`
- **Not mentioned** in the profile README

**Still copied into the distribution**
- `temp/skills/sage-waggle/`
- `temp/docs/`

Personal memory is built through normal agent use, not a bundled seed file. Say the word when you want this implemented.

---

**User**

look at @temp/config.yaml as an example

---

**Cursor**

Updating the plan to use `temp/config.yaml` as the config template instead of the hand-written example.


Updated the plan to use [`temp/config.yaml`](temp/config.yaml) as the config source instead of a hand-written minimal example.

**Changes:**

- **Source inventory:** `temp/config.yaml` → adapt into `hermes-profile/config.yaml`
- **Section 3:** Copy the real file and only trim optional items (personalities, spotify plugin, comment blocks)
- **Keep as-is:** Ollama setup (`gemma4:31b`, `http://127.0.0.1:11434/v1`), `custom_providers.sage-thor-H020-gemma4-31b`, full `platform_toolsets.cli`, `web.backend: ddgs`, `browser.cloud_provider: local`, memory limits
- **Copy step:** `cp temp/config.yaml hermes-profile/config.yaml` then apply trims
- Fixed `SAGE_PORTAL_TOKEN` to `required: false` (read-only MCP works without it)

No secrets in the example config — safe to ship after optional trims. Say the word when you want this implemented.

---

**User**

Oh, and in your tmux instructions, please include how to do this: set-option -g history-limit 50000 in the .tmux.conf and then maybe give them this script:

write-tmux.sh
#!/bin/sh

# Confirm we're in a tmux session and capture full scrollback WITH ANSI escapes (-e), from start of history (-S -)
if [ -n "$TMUX" ]; then
  TS=$(date +%Y%m%d_%H%M%S)
  OUT=~/AI-projects/tmux-logs/transcript_${TS}.ansi
  tmux capture-pane -p -e -S - > "$OUT"
  echo "saved: $OUT"
  wc -l "$OUT"; ls -l "$OUT"
else
  echo "NOT inside a tmux session (\$TMUX is empty)."
  echo "Available tmux sessions:"
  tmux ls 2>/dev/null || echo "  (tmux server not running / no sessions)"
fi

It makes "less -R" a lot of fun

---

**Cursor**

Adding tmux scrollback instructions to the plan. Checking the current tmux section in `hermes-agent.md`.


Updated the plan with tmux scrollback documentation for [`hermes-agent.md`](hermes-agent.md) Step 5:

**One-time setup**
- Add `set-option -g history-limit 50000` to `~/.tmux.conf`

**`scripts/write-tmux.sh`**
- Add the script to the repo (not in `hermes-profile/`)
- Captures full pane history with ANSI colors via `tmux capture-pane -p -e -S -`
- Saves to `~/AI-projects/tmux-logs/transcript_<timestamp>.ansi`
- Includes `mkdir -p` for the log directory

**Participant docs**
- Run from inside the `hermes` tmux session
- Review with `less -R` to keep colors

This is part of the `update-readmes` todo when the plan is executed. Say the word to implement.

---

**User**

Implement the plan as specified, it is attached for your reference. Do NOT edit the plan file itself.

To-do's from the plan have already been created. Do not create them again. Mark them as in_progress as you work, starting with the first one. Don't stop until you have completed all the to-dos.

---

**Cursor**

Implementing the Sage profile distribution per the plan. Starting with copying assets from `temp/`.


Creating manifest files and applying config trims.


The Sage Hermes profile distribution is complete. Summary:

## `hermes-profile/` — ready to install

| File | Status |
|------|--------|
| `distribution.yaml` | Created (`name: sage`, v1.0.0) |
| `SOUL.md` | Created with camp personality + domain facts from `MEMORY.starter.md` |
| `config.yaml` | Adapted from `temp/` (Ollama `gemma4:31b`, provider renamed to `local-sage-thor`, spotify removed) |
| `mcp.json` | Sage MCP pre-wired |
| `.gitignore` | Merged Hermes + temp exclusions |
| `skills/sage-waggle/` | Copied (~70 reference files) |
| `docs/` | Copied (4 files) |
| `README.md` | Rewritten for `hermes profile install` flow |

`MEMORY.starter.md` was **not** shipped — facts are embedded in `SOUL.md` only.

## Docs & scripts

- **`hermes-agent.md`**: `<org>` → `FranciscoLozCoding`; Step 5 expanded with tmux scrollback (`history-limit 50000`) and `scripts/write-tmux.sh`
- **`scripts/write-tmux.sh`**: Created and made executable

## Verification

```bash
hermes profile install ./hermes-profile --name sage-test -y --alias  # ✓
hermes profile info sage-test                                          # ✓ v1.0.0
hermes doctor -p sage-test                                             # ✓ (only expected .env missing)
hermes skills list -p sage-test                                        # ✓ sage-waggle enabled
hermes profile delete sage-test --yes                                  # ✓ cleaned up
```

No secrets found in staged profile files — only placeholders and env var descriptions.

## Install on Thor

```bash
git clone https://github.com/FranciscoLozCoding/summer-camp-2026.git
cd summer-camp-2026
hermes profile install ./hermes-profile --name sage --alias
```

Smoke test prompt: *"Using the sage-waggle skill, why do Sage ECR builds currently fail, and what's the workaround?"*

`temp/` is unchanged as specified. Changes are uncommitted — say if you want a commit or PR.

---

**User**

write this down somewhere so students dont forget to do this

At the end of the summer camp we should make the students publish their "brain" so we can update this agent

---

**Cursor**

Finding the best place to document end-of-camp brain publishing for students.


Adding an end-of-camp reminder in the student-facing docs: `hermes-agent.md` (main guide) and `hermes-profile/README.md`.


Added an end-of-camp reminder in three places students are likely to see:

### 1. [`hermes-agent.md`](hermes-agent.md) — Part 3, new section **"End of camp — publish your brain (required)"**
- Callout that this is required before leaving (Jul 28)
- Table of what to share vs. keep private
- Steps: review `~/.hermes/profiles/sage/`, copy into `hermes-profile/`, open a PR
- Optional `hermes profile export` path for instructor review

### 2. [`hermes-profile/README.md`](hermes-profile/README.md) — short **"End of camp — publish your brain"** section
- Links to the full checklist in `hermes-agent.md`

### 3. [`README.md`](README.md) — **Baseline Deliverables**
- Fourth bullet: publish your Hermes brain back to `hermes-profile/` so the shared agent can be updated

The main workflow for students: sanitize learnings from their personal brain → PR to `hermes-profile/` (or export to an instructor) → organizers bump `distribution.yaml` version → future students run `hermes profile update sage`.

---

**User**

add nrp endpoint as well into a hermes custom model. Select gpt-oss (openai/gpt-oss-120b)

https://nrp.ai/documentation/userdocs/ai/llm-managed/ 
https://nrp.ai/documentation/userdocs/ai/llm-managed/models/ 
https://nrp.ai/documentation/userdocs/ai/llm-managed/api-access/ 
https://nrp.ai/documentation/userdocs/ai/llm-managed/client-configs/ 

---

**Cursor**

Reviewing how Hermes custom providers are configured and where inference options are documented.


Checking how the guide table and comparison section are structured for a third inference option:


I have enough context. The profile already uses `custom_providers` for Ollama; NRP fits the same pattern as an optional named provider with `gpt-oss` as default.


---

**User**

Implement the plan as specified, it is attached for your reference. Do NOT edit the plan file itself.

To-do's from the plan have already been created. Do not create them again. Mark them as in_progress as you work, starting with the first one. Don't stop until you have completed all the to-dos.

---

**Cursor**

Implementing the NRP provider per the plan. Starting with `hermes-profile/config.yaml`.


NRP Managed LLM support is in place. Summary:

### Profile config ([`hermes-profile/config.yaml`](hermes-profile/config.yaml))
Added `nrp` custom provider:
- Endpoint: `https://ellm.nrp-nautilus.io/v1`
- Model: `gpt-oss` (131,072 context)
- Key env: `NRP_LLM_API_KEY`
- Ollama (`gemma4:31b`) remains the default

### Manifest ([`hermes-profile/distribution.yaml`](hermes-profile/distribution.yaml))
- Version bumped to **1.0.1**
- Optional `NRP_LLM_API_KEY` in `env_requires`

### Docs
- **[`hermes-agent.md`](hermes-agent.md)**: New **Part 2B — NRP Managed LLMs** (token setup, verify curl, `hermes model` switch)
- Comparison table expanded to 3 options (Ollama / NRP / NVIDIA)
- Switching section updated (`local-sage-thor`, `nrp`, NVIDIA NIM)
- **[`hermes-profile/README.md`](hermes-profile/README.md)**: `NRP_LLM_API_KEY` in env table, config blurb updated

### Verification
- `hermes profile install` → v1.0.1 with `NRP_LLM_API_KEY` listed
- `nrp` / `gpt-oss` present in installed config
- `hermes doctor` passed (expected `.env` missing only)
- No secrets in profile files

Students with NRP access add `NRP_LLM_API_KEY` to `.env`, then run `hermes model` and select provider **`nrp`** / model **`gpt-oss`**.

---

**User**

add a guide for token economy after switching between approaches

---

**Cursor**

Reviewing the switching section and Hermes token/context features to draft a token economy guide.


Adding a token economy section after switching approaches and linking it from the guide table.


Added **Token economy** to [`hermes-agent.md`](hermes-agent.md) right after [Switching between approaches](hermes-agent.md#switching-between-approaches), and linked it from the guide table at the top.

The section covers:

1. **What costs what** — Ollama (shared GPU), NRP (fair use), NVIDIA (credits)
2. **What fills context** — SOUL, skills, memory (~2.2K chars), tool output, history
3. **Hermes controls** — `/usage`, `/compress`, fresh sessions, delegation; camp defaults from `config.yaml`
4. **Switching mid-session** — prompt-cache reset warning and a practical workflow
5. **Provider-specific tips** — Ollama, NRP (`cache_salt`, fair use), NVIDIA credits
6. **Quick checklist** — habits students can follow daily

No profile config changes — this is documentation only.

---

**User**

this is feedback given by a student 

I tested the Wisp profile on H00F and it worked really well. I was able to install it on my first attempt, and the agent correctly identified the node using the sage-waggle skill, explained the Waggle stack well, and the Sage → Wisp rename came through. One thing I noticed for the camp: I was using gemma4:31b with the full 256K context, so the first response took about 3.5 minutes and it feels like it's frozen. I had the same issue earlier this week and fixed it by capping the context (num_ctx 65536 or OLLAMA_CONTEXT_LENGTH), so I'd recommend using a context-capped model.
https://github.com/Miguel-Hernandez1/project-sage-notes/blob/main/docs/03-hermes-on-thor.md 

Also, Wisp suggests building plugins with Podman, but I just tested and podman --init still fails on the Thors because catatonit isn't installed (exit 125). Im not sure if there's already a plan for this, but pre-installing catatonit or defaulting to the local backend might be worth it if it's simpler for the camp.

- build plugins with pluginctl 
https://sagecontinuum.org/docs/reference-guides/pluginctl 
https://github.com/waggle-sensor/edge-scheduler/tree/main/docs/pluginctl#readme 
https://github.com/waggle-sensor/edge-scheduler/blob/main/docs/pluginctl/tutorial_build.md 
root@sgt-thor-1423225065758-H020:~# pluginctl -h
Usage:
  pluginctl [FLAGS] [COMMANDS] [flags]
  pluginctl [command]

Available Commands:
  build       Build plugin
  completion  
  deploy      Deploy a plugin
  exec        Execute a command on plugin
  help        Help about any command
  logs        Print logs of a plugin
  profile     Profile performance of a plugin
  ps          Query plugin list
  rm          Remove plugin
  run         Run a plugin

Flags:
      --debug               flag to debug
  -h, --help                help for pluginctl
      --kubeconfig string   path to the kubeconfig file (default "/etc/rancher/k3s/k3s.yaml")

Use "pluginctl [command] --help" for more information about a command.

---

**Cursor**

Reviewing current docs and profile config against the student feedback.


Checking Part 1 structure and whether a Thor troubleshooting section exists:


Confirming the profile already uses `terminal.backend: local`; the gaps are context-capped Ollama defaults and clearer Thor/pluginctl guidance.


**Thor model default**

> **For the context-capped Ollama model, should the camp profile default switch to `gemma4-64k` (organizers pre-create via Modelfile on each Thor before camp), or keep `gemma4:31b` as default and only document the Modelfile step for students to run themselves?**
> - Switch profile default to gemma4-64k (organizers pre-create on Thors)
> - Keep gemma4:31b default; document Modelfile step as recommended post-install ✔

---

**User**

Implement the plan as specified, it is attached for your reference. Do NOT edit the plan file itself.

To-do's from the plan have already been created. Do not create them again. Mark them as in_progress as you work, starting with the first one. Don't stop until you have completed all the to-dos.

---

**Cursor**

Implementing Thor student feedback updates. Starting with `hermes-agent.md`.


Implemented all Thor student feedback updates. Summary:

### [`hermes-agent.md`](hermes-agent.md)
- **Step 4B** — Cap Ollama context with `gemma4-64k` Modelfile (`num_ctx 65536`); links to [Miguel's H00F notes](https://github.com/Miguel-Hernandez1/project-sage-notes/blob/main/docs/03-hermes-on-thor.md)
- **Organizer fleet prep** — optional `gemma4-64k` pre-create, `catatonit`, sandbox image pre-pull
- **Troubleshooting** — slow first response, Docker exit 125 / `local` backend rationale, **`pluginctl build`** workflow with Sage docs links
- **Token economy** stub — points to full guide + Step 4B quick fix

### [`token-economy.md`](token-economy.md)
- New **Thor first response** section: 3.5 min symptom, `ollama ps` verification, Modelfile procedure, shared GPU etiquette

### [`hermes-profile/`](hermes-profile/)
- **README** — Thor tips (H00F-tested) + organizer fleet prep table
- **config.yaml** — comment explaining Modelfile vs Hermes `context_length`
- **distribution.yaml** — version **1.0.2**

### [`sage-waggle/SKILL.md`](hermes-profile/skills/sage-waggle/SKILL.md)
- Camp default callout: `sudo pluginctl build` first; `podman` only for ECR side-load

**Unchanged (per plan):** default model stays `gemma4:31b`; `terminal.backend: local` already correct.

**Verified:** `hermes profile install` succeeds at v1.0.2.

---

**User**

add a md file in @hermes-profile/skills/sage-waggle/references/ about pluginctl

---

**Cursor**

Reviewing existing reference file style and current pluginctl documentation before adding the new reference.


Creating a camp-focused `pluginctl` reference and linking it from the skill.


Added [`hermes-profile/skills/sage-waggie/references/pluginctl-camp-guide.md`](hermes-profile/skills/sage-waggle/references/pluginctl-camp-guide.md) — a camp-focused `pluginctl` reference covering:

- What `pluginctl` is and how it differs from `sesctl`/ECR
- Thor prerequisites (`sudo`, k3s/WES, official doc links)
- **Camp workflow:** `build` → `run` → `logs` → `rm` (with hello-world example)
- Command table and common flags
- Dockerfile rules on Thor (fully-qualified `docker.io/...` base, ENTRYPOINT)
- `pluginctl` vs `podman` vs Hermes terminal sandbox
- Troubleshooting table (RBAC, registry down, GPU on host, ECR runc bug)
- Pointers to deeper skill refs

Also updated [`SKILL.md`](hermes-profile/skills/sage-waggle/SKILL.md) so the camp default callout links to this file and it's listed in the references index.

---

**User**

update the skills to use this for referencing pywaggle package https://github.com/waggle-sensor/pywaggle 

---

**Cursor**

Updated the skill so [waggle-sensor/pywaggle](https://github.com/waggle-sensor/pywaggle) is the canonical SDK reference.

### Primary
- **[`SKILL.md`](hermes-profile/skills/sage-waggle/SKILL.md)** — Plugin Development now links the repo, install extras, [Writing a plugin](https://github.com/waggle-sensor/pywaggle/blob/main/docs/writing-a-plugin.md), and `src/waggle`; See Also + GitHub orgs point at the same URL
- **[`SOUL.md`](hermes-profile/SOUL.md)** — pywaggle role bullet links to the repo

### Source citations in refs
Upload/identity notes that said “verified against pywaggle source” now link the GitHub repo, including:
`pywaggle-upload-naming-and-timestamps.md`, `pywaggle-capture-time-stamping.md`, `node-identity-and-upload-contract.md`, `image-upload-provenance-and-linking.md`, `image-metadata-naming-and-eventlog-linking.md`, `linking-images-to-event-log-and-uniqueness.md`, `upload-naming-metadata-and-provenance.md`, `plugin-duration-performance-telemetry.md`, `direct-node-testing.md`, `ml-plugin-patterns.md`

### Docs
- **[`docs/pywaggle2-design.md`](hermes-profile/docs/pywaggle2-design.md)** — upstream-RFC mentions use the full GitHub URL

