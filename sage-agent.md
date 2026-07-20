# Sage Agent Setup Guide

Run the **Sage edge agent** on your assigned node. This is an autonomous science agent that lives on the node itself: you hand it a task in plain English and it drives PTZ cameras and sensors, runs vision models (YOLO, BioCLIP 2, Gemma), reasons with an LLM, and reports back. Wildfire watch, animal tracking, sky observation, that kind of work.

Unlike Hermes, this is not a general-purpose assistant you chat with. It is the runtime that ships to the node, and you talk to it with one command:

```bash
python -m ptz_node run "your task here"
```

You do not need a camera or a GPU to start. A simulated PTZ camera (a large stitched panorama image) is built in, so everything in this guide works on a Thor blade, a Jetson, or your own laptop.

| Section | Best for |
| ------- | -------- |
| [Part 1 - Install and first run](#part-1-install-and-first-run) | Getting the agent running on your node or laptop |
| [Part 2 - Choosing an LLM](#part-2-choosing-an-llm) | Ollama on the node vs OpenRouter vs argo-proxy |
| [Part 3 - Using the agent](#part-3-using-the-agent) | Tasks, demos, real cameras, examples |
| [Part 4 - Building your own skills and tools](#part-4-building-your-own-skills-and-tools) | Adding capabilities for your application area |
| [Troubleshooting](#troubleshooting) | When something breaks |

**Docs:** the repo ships a longer reference at [`sage-agent/docs/node-setup.md`](https://github.com/waggle-sensor/sage-agent/blob/main/docs/node-setup.md). This page is the camp-flavored version.

---

## How it fits together

```
  Laptop (SSH)                Node (Thor / Jetson / laptop sim)
┌──────────────────┐          ┌─────────────────────────────────────┐
│  Terminal only   │   SSH    │  Reasoning LLM (Ollama or cloud)    │
│  tmux attach     │─────────►│  Agent loop (python -m ptz_node)    │
│                  │          │  Vision: YOLO / BioCLIP 2 / Gemma   │
│                  │          │  Sensor gateway → PTZ cam, sensors  │
└──────────────────┘          └─────────────────────────────────────┘
```

Three pieces plug together:

- **A reasoning LLM**, the brain. Local (Ollama on the node) or cloud (OpenRouter, Anthropic, or ANL's argo-proxy). Swappable via config, no code changes.
- **Vision backends** that look at camera frames: YOLO for objects, BioCLIP 2 for species and taxa, Gemma for scene descriptions.
- **A sensor gateway**, the only thing that touches hardware. It talks to a real PTZ camera or to the simulated one.

The agent never touches hardware directly, only through the gateway. That is also why the sim mode is a faithful stand-in: the agent cannot tell the difference.


---

# Part 1: Install and first run

## Prerequisites

- [ ] SSH access to your assigned node (Thor blade or Jetson), or just your own Mac/Linux laptop for sim work
- [ ] Python 3.10, 3.11, or 3.12 on the machine (the bootstrap script sorts this out, including a micromamba fallback if the system Python is too old)
- [ ] One LLM option from [Part 2](#part-2-choosing-an-llm). On camp Thors, Ollama with `gemma4:31b` is usually already there, so you may need nothing at all.

No camera required. No sudo required.

## Step 1 - Get the code onto the node

Clone directly on the node:

```bash
git clone https://github.com/waggle-sensor/sage-agent.git ~/sage-agent
cd ~/sage-agent
```

Or, if you develop on your laptop and push to the node (the common workflow once you start editing), use the sync script from your laptop. It copies over SSH and skips `.venv`, `.local`, and caches:

```bash
# from your laptop, in the sage-agent repo root:
bash scripts/sync_to_spark.sh <your-user>@<node-host>:/home/<your-user>/sage-agent
```

One thing to know: the virtual environment never travels with the code. `.venv/` is per-machine, so you create it fresh on each node in Step 2. If you ever see `ModuleNotFoundError: No module named 'langchain_core'`, the venv is missing or not activated.

## Step 2 - Create the Python environment

From the repo root on the node:

```bash
bash scripts/bootstrap_python311.sh
source .venv/bin/activate
```

Your prompt should now start with `(.venv)`. You have to re-activate in every new SSH session:

```bash
cd ~/sage-agent && source .venv/bin/activate
```

## Step 3 - Install dependencies

```bash
pip install -r requirements.txt            # core: agent loop, sensor gateway, sim PTZ
pip install -r requirements-vision.txt     # YOLO and BioCLIP 2 (optional but recommended)
```

| File | Needed for | Skip it if |
| ---- | ---------- | ---------- |
| `requirements.txt` | The agent itself, sim PTZ, sensors, all LLM clients | Never skip this one |
| `requirements-vision.txt` | `ptz_detect` with YOLO and BioCLIP | You only want scene captions via Gemma/Ollama |
| `requirements-argo.txt` | The ANL argo-proxy LLM gateway | You use OpenRouter, Anthropic, or Ollama |

Two things to expect with vision. YOLO and BioCLIP need a GPU build of PyTorch on Jetson-class hardware; if it is not installed, those detectors show up as unavailable and everything else still runs. And the first BioCLIP call downloads about 4.4 GB of model weights to `~/.cache/huggingface`. That happens once. Let it finish.

## Step 4 - Point it at an LLM

The quick version for a camp Thor (Ollama and `gemma4:31b` are usually already installed):

```bash
export PTZ_GRAPH_CONFIG=$PWD/config/default.yaml
export MSA_PTZ_BACKEND=sim
```

Other options (cloud keys, different models) are in [Part 2](#part-2-choosing-an-llm).

## Step 5 - Preflight checks

These need no LLM and confirm the node is healthy:

```bash
python -m ptz_node doctor          # environment, model, and camera checks
python -m ptz_node devices         # list every device the gateway sees
python -m ptz_node gateway-smoke   # exercise the camera and sensors end to end
```

`doctor` is the one to lean on. It tells you exactly what is missing and how to fix it. Two flags it commonly raises:

- `ollama_model_pulled` failed: you chose a local model that is not pulled yet. Run the `ollama pull <model>` command it prints. Thors usually have models pre-pulled; Orin nodes usually do not.
- Vision or `gemma4` warnings: fine to ignore unless you actually need those detectors.


## Step 6 - First run

```bash
python -m ptz_node run "List the devices, check detector status, and summarize node readiness."
```

If that prints a summary and a `# trace:` path at the end, you are done with setup.

---

# Part 2: Choosing an LLM

The agent reads its settings from a YAML config selected with the `PTZ_GRAPH_CONFIG` environment variable. Secrets always come from environment variables, never from the YAML files.

| Config | Reasoning LLM | Camera | Use when |
| ------ | ------------- | ------ | -------- |
| `config/default.yaml` | Ollama (local) | sim | Camp Thors, offline work, no API key needed |
| `config/dgx_spark.yaml` | OpenRouter (cloud) | sim | Anywhere with internet; just needs an OpenRouter key |
| `config/local.yaml` | argo-proxy (ANL) | sim | On the ANL network, or a laptop with an SSH tunnel |

## Option A - Ollama on the node (camp default)

```bash
# install once if missing: curl -fsSL https://ollama.com/install.sh | sh
ollama serve &                  # skip if it is already running as a service
ollama pull gemma4:31b          # the model must support tool calling
export PTZ_GRAPH_CONFIG=$PWD/config/default.yaml
export MSA_PTZ_BACKEND=sim
```

Memory note for the hardware nerds: on a 64 GB Orin, a reasoning LLM plus a VLM plus a detector is a tight fit, and the agent lazy-loads and evicts models to cope. On a 122 GB Thor you have much more headroom. If runs feel slow, this is usually why.

## Option B - Cloud LLM via OpenRouter

```bash
export PTZ_GRAPH_CONFIG=$PWD/config/dgx_spark.yaml
export OPENROUTER_API_KEY=sk-or-...        # from https://openrouter.ai/keys
export MSA_PTZ_BACKEND=sim
```

Want a different model? Do not edit the tracked YAML on the node, because a re-sync would overwrite it. Drop a local override file instead. It is gitignored and gets merged last:

```yaml
# config/argo_proxy.local.yaml, overrides anything above it
model:
  provider: openrouter
  model: openai/gpt-4o          # any tool-calling slug from openrouter.ai/models
```

## Option C - argo-proxy (ANL network only)

```bash
bash scripts/setup_argo_proxy.sh -u YOUR_ANL_USER -m gpt-4o
export PTZ_GRAPH_CONFIG=$PWD/config/local.yaml
python -m ptz_node argo test
```

## Keeping the environment variables around

`export` lines vanish when you close the shell. Add them to `~/.bashrc` (or `~/.zshrc`) and `source` it. Keep API keys out of any file that gets committed or synced.

---

# Part 3: Using the agent

## Running tasks

```bash
python -m ptz_node run "Take a snapshot, run a tiled YOLO detection, and tell me what you see."
```

What to expect while it runs:

- Live progress prints as it works, lines like `[  3s] → ptz_detect {"model":"yolo","tile":true}` followed by `[ 41s] ✓ ptz_detect`. If it looks stuck, check whether a step is just slow (model loading, cloud call); the timestamps keep moving. Add `--quiet` to hide these.
- The final answer prints at the end, followed by a `# trace:` path.
- A full step-by-step trace lands in `.local/runs/<id>/summary.txt`. Read it whenever a run does something surprising. It is also the fastest thing to share when you ask for help.

Flags worth knowing:

```bash
python -m ptz_node run "<task>" --limit 200    # allow more tool/LLM cycles for big jobs
python -m ptz_node run "<task>" --quiet        # suppress the live progress lines
```

## Example prompts to try

```bash
python -m ptz_node run "Pan the camera across the horizon and report anything that looks like smoke."
python -m ptz_node run "Take a snapshot and identify any birds or animals with BioCLIP."
python -m ptz_node run "Read the system stats sensor and tell me if this node is under memory pressure."
python -m ptz_node run "Describe the current scene and estimate cloud cover."
```

The agent decides which tools to call: PTZ moves, snapshots, `ptz_detect` (YOLO/BioCLIP), `ptz_caption` (scene descriptions), sensor reads, and skills.


## Demos: canned workflows

Huge open-ended prompts ("scan the entire panorama with every model") can run for dozens of LLM cycles. For big sweeps, use a demo instead. Demos are pre-scripted Sage workflows that run as one bounded, reliable call, print progress, and save a JSON report to `.local/demos/`:

```bash
python -m ptz_node skill run demo --args '{"action":"list"}'                 # see them all
python -m ptz_node skill run demo --args '{"name":"edge_gateway_preflight"}' # no LLM, no vision
python -m ptz_node skill run demo --args '{"name":"wildfire_smoke_patrol"}'
python -m ptz_node skill run demo --args '{"name":"panorama_scan"}'          # full sweep, every backend
```

Available demos: `edge_gateway_preflight`, `ptz_multimodel_scientific_survey`, `wildfire_smoke_patrol`, `aves_biodiversity_scan`, `land_cover_agriculture_scene`, and `panorama_scan`. The agent can also route to these itself; ask it to scan the whole panorama and it picks `panorama_scan` on its own.

`panorama_scan` runs under a time budget and skips any backend that is not installed, so it cannot hang. You can limit the vision models:

```bash
python -m ptz_node skill run demo --args '{"name":"panorama_scan","backends":["yolo","bioclip"]}'
```

## Connecting a real PTZ camera

If you set up a camera from the [Remote Sensor guide](Remote-Sensor-Setup.md), the agent can find and configure it. The `sensor_discovery` skill does this in three steps with retry caps and a time budget:

```bash
python -m ptz_node skill run sensor_discovery --args '{"action":"scan"}'
python -m ptz_node skill run sensor_discovery --args '{"action":"identify","ip":"192.168.8.55"}'
python -m ptz_node skill run sensor_discovery --args '{"action":"configure","ip":"192.168.8.55"}'
```

Or let the agent drive:

```bash
python -m ptz_node run "Find the PTZ camera on the network and tell me how to set it up."
```

It hands back the exact environment variables to set. For a Reolink camera:

```bash
export MSA_PTZ_BACKEND=reolink
export REOLINK_IP=192.168.8.55
export REOLINK_USER=admin
export REOLINK_PASSWORD=...        # the skill asks; it never guesses or stores this
python -m ptz_node devices         # ptz_primary should now show backend=reolink
```

Never commit a camera password to a file, and never put one in a screenshot.


## The test suite

The repo ships Sage science test cases: the same scenarios as the demos, but judged by the LLM. Good for checking the whole stack after changes:

```bash
python -m ptz_node test --list                          # list cases
python -m ptz_node test --id edge_gateway_preflight     # one case, no vision needed
python -m ptz_node test --all                           # everything
```

## Long runs in tmux

Same advice as Hermes: run long jobs inside tmux so a dropped SSH session does not kill them.

```bash
tmux new -s sage-agent
python -m ptz_node run "..."
# detach: Ctrl-b then d, reattach: tmux attach -t sage-agent
```

---

# Part 4: Building your own skills and tools

This is where camp projects come in. The base agent already knows how to move a camera, run detectors, and read sensors. What it does not know is your application area: your species of interest, your patrol pattern, your analysis, your sensor. That is what you add.

`ptz_node/` is the engine; treat it as read-only and add capabilities at the edges. Pick the lightest layer that fits:

| You want to... | Add a... | Where |
| -------------- | -------- | ----- |
| Change the model, provider, or a knob | Config entry | `config/*.yaml` (or your gitignored `config/argo_proxy.local.yaml`) |
| Support a new sensor or device | Driver | `ptz_node/sensor_gateway/drivers/*.py`, subclass `BaseDriver` |
| Add a scheduled or on-demand capability | Skill | `ptz_node/skills/*.py`, subclass `BaseSkill`, auto-discovered |
| Give the agent a new verb it can call | Tool | a `@tool` function in `ptz_node/langchain_tools.py` |
| Add a science scenario to the test suite | Test case | `config/agentic_test_cases.yaml` |

Most projects only need a skill, so start there.

## Writing a skill

A skill is a self-contained routine that can chain several camera and sensor calls: a patrol, a survey, a periodic measurement. Subclass `BaseSkill`, drop the file in `ptz_node/skills/`, and it is auto-discovered at startup. No registration code, no wiring.

Here is a complete working skill. Save it as `ptz_node/skills/bird_survey.py`:

```python
"""Survey a few camera headings and count birds at each one."""

from __future__ import annotations

from ptz_node.skills.base import BaseSkill, SkillContext, SkillResult


class BirdSurveySkill(BaseSkill):
    name = "bird_survey"
    description = (
        "Point the PTZ camera at several pan headings and run a YOLO bird "
        "count at each. Args: headings (list of pan degrees, default "
        "[0, 90, 180, 270]). Takes roughly a minute per heading."
    )
    agent_callable = True   # expose to the LLM so it can call this itself

    def run(self, ctx: SkillContext) -> SkillResult:
        gateway = ctx.gateway()
        headings = ctx.args.get("headings", [0, 90, 180, 270])
        counts = {}
        for pan in headings:
            gateway.invoke("ptz_primary", "move_to", {"pan": pan, "tilt": 0})
            result = gateway.invoke("ptz_primary", "detect",
                                    {"model": "yolo", "targets": "bird"})
            counts[str(pan)] = len(result.get("detections", []))
        total = sum(counts.values())
        return SkillResult(
            ok=True,
            skill=self.name,
            summary=f"Counted {total} birds across {len(headings)} headings.",
            data={"counts_by_heading": counts},
        )
```

The pieces that matter:

- `name` and `description` are what the rest of the system sees. The description is written for the LLM: it says what the skill does, what args it takes, and how long it runs, because that text is how the model decides when to use it.
- `agent_callable = True` means the reasoning LLM can invoke it during a run. Leave it `False` for things only humans or the scheduler should trigger.
- `ctx.gateway()` is your handle to all hardware. Skills never open sockets to cameras directly.
- Return a `SkillResult` with `ok`, a one-line `summary`, and structured `data`. If something fails, return `ok=False` with the error in the summary instead of raising; a crash takes the whole agent loop down with it.

Test it immediately, no LLM needed:

```bash
python -m ptz_node skill list                  # your skill should appear
python -m ptz_node skill run bird_survey --args '{"headings":[0, 180]}'
```

Then confirm the agent discovers it on its own:

```bash
python -m ptz_node run "Survey the area for birds and tell me the busiest heading."
```

Check `.local/runs/<id>/summary.txt` to see whether the model actually picked your skill. If it did not, the fix is almost always a better `description`.

## Writing a tool

A tool is one atomic verb the LLM calls in a single step, like `ptz_move_to` or `ptz_detect`. Add one when your capability is a single action rather than a routine. Tools live as `@tool` functions inside `build_gateway_tools()` in `ptz_node/langchain_tools.py`:

```python
@tool
def soil_moisture_read(depth_cm: int = 10) -> str:
    """Read the soil moisture probe at a given depth in cm (10, 30, or 60).
    Fast and cheap; returns volumetric water content as JSON."""
    try:
        result = gateway.invoke("sensor:soil_probe", "read", {"depth": depth_cm})
        return json.dumps({"ok": True, **result})
    except Exception as exc:
        return json.dumps({"ok": False, "error": str(exc)})
```

Same rules as skills: the docstring is the model's only instruction manual, so be concrete about arguments and cost, and catch exceptions and return `{"ok": false, ...}` instead of raising.

## Adding a driver for new hardware

If you brought your own sensor on hardware day, it plugs in as a driver: subclass `BaseDriver` in `ptz_node/sensor_gateway/drivers/`, and the gateway picks it up. Once the driver reports its capabilities, the generic tools (`sensor_read`, `sensor_invoke`) work against it with no further code, and `python -m ptz_node devices` will list it. Look at `msa_sensor.py` in that directory for the pattern.

## Ground rules that keep the node alive in the field

- Skills, tools, and drivers return structured errors instead of crashing the loop.
- Guard optional imports (`try/except ImportError`) so a missing dependency degrades gracefully instead of breaking startup.
- Put timeouts on all I/O. Rural deployments lose network constantly.
- Note rough memory and latency cost in descriptions. On a 64 GB Orin, the reasoning LLM, a VLM, and a detector barely fit together, and the model plans better when it knows what is heavy.

## Project workflow

A rhythm that works: prototype on your laptop in sim mode, sync to your node with `scripts/sync_to_spark.sh`, run `doctor` and `gateway-smoke`, then add a scenario to `config/agentic_test_cases.yaml` so `python -m ptz_node test` covers your feature. If you keep your skills outside the repo, point `PTZ_GRAPH_SKILLS_DIR` at your own directory and they are discovered from there instead.

## Where things live

| Path | What it is |
| ---- | ---------- |
| `ptz_node/` | The agent engine. Do not edit unless you know why |
| `config/*.yaml` | Configs you select with `PTZ_GRAPH_CONFIG` |
| `config/argo_proxy.local.yaml` | Your personal overrides (gitignored) |
| `.local/runs/<id>/summary.txt` | Per-run trace. Read this after a weird run |
| `.local/demos/` | JSON reports from demo runs |
| `.local/debug/doctor.json` | The last `doctor` report |
| `.venv/` | Your Python environment (per-machine, never synced) |

Everything the agent writes at runtime goes under `.local/`, which is git-ignored, so it is safe to delete for a clean slate.

---

# Troubleshooting

| Symptom | Cause and fix |
| ------- | ------------- |
| `ModuleNotFoundError: No module named 'langchain_core'` | Venv is missing or not active. `bash scripts/bootstrap_python311.sh && source .venv/bin/activate`, then re-install requirements. |
| Prompt has no `(.venv)` prefix | You are on system Python. `source .venv/bin/activate`. |
| `doctor` says `ollama_model_pulled` failed | Run the `ollama pull <model>` command from the doctor output. Common on Orin nodes, which ship with no models pulled. |
| `ollama serve` says "address already in use" | Ollama is already running. Do nothing. |
| A run looks like it is hanging | Probably just slow: model download, model load, or a big prompt. Watch the `[ Ns ]` timestamps, and run `watch -n2 nvidia-smi` in a second SSH session to confirm GPU activity. For big sweeps, use a demo instead. |
| The first vision call takes forever | BioCLIP is downloading ~4.4 GB to `~/.cache/huggingface`. One-time cost, let it finish. |
| Vision detectors show as unavailable | GPU PyTorch is not installed (`requirements-vision.txt`). Optional; Gemma captions via Ollama still work. |
| `command not found: argo-proxy` | Not installed or venv not active. `source .venv/bin/activate && pip install -r requirements-argo.txt`. |
| Imports fail when running `python -m ptz_node` on a node | Run from the repo root, and export `PYTHONPATH=$PWD` if needed. |

When in doubt, run `python -m ptz_node doctor` and read `.local/runs/<id>/summary.txt`.

## Quick command reference

```bash
python -m ptz_node doctor                 # health check, run this first
python -m ptz_node devices                # list cameras and sensors
python -m ptz_node gateway-smoke          # test the hardware path, no LLM
python -m ptz_node read sensor:system_stats            # one sensor reading
python -m ptz_node run "<task>"           # full agent loop
python -m ptz_node skill run demo --args '{"action":"list"}'              # canned workflows
python -m ptz_node skill run sensor_discovery --args '{"action":"scan"}'  # find cameras
python -m ptz_node test --all             # Sage test cases
```
