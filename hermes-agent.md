# Hermes Agent Setup Guide

Run **Hermes Agent on your laptop** while inference happens on a **remote GPU** or a **hosted API**. Hermes handles local files, terminal, and tools; the model runs elsewhere.

| Guide | Best for |
| ----- | -------- |
| [Part 1 — Thor + Ollama](#part-1-thor--ollama) | You have SSH access to a Thor GPU with Ollama already running |
| [Part 2 — NVIDIA Hosted APIs](#part-2-nvidia-hosted-apis) | No Thor GPU — use NVIDIA Build's serverless inference |
| [Comparison](#thor-vs-nvidia-hosted-apis) | Choosing between the two approaches |
| [ Switching between the two approaches](#switching-between-the-two-approaches) | Switching between the two approaches |

**Docs:** [Hermes Documentation](https://hermes-agent.nousresearch.com/docs/)

---

# Part 1: Thor + Ollama

Hermes runs locally. Model inference goes through an **SSH tunnel** to Ollama on the Thor.

## At a glance

```
  Laptop                          Thor GPU
┌─────────────────────┐           ┌─────────────────────┐
│  Hermes Agent       │           │  Ollama             │
│  Local files        │  SSH      │  LLM on NVIDIA GPU  │
│  Local terminal     │  Tunnel   │                     │
│  localhost:11434 ───┼──────────►│  localhost:11434    │
└─────────────────────┘  :11434   └─────────────────────┘
```

**Flow:** Install Hermes → Open SSH tunnel → Verify connection → Launch

---

## Prerequisites

- [ ] Laptop with terminal access
- [ ] SSH access to a Thor GPU
- [ ] Ollama installed and running on the Thor
- [ ] At least one model pulled on the Thor (e.g. `gemma4:31b`)

---

## Step 1 — Install Hermes

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

During setup, work through the installer in this order. Values marked *example* depend on your Thor model.

### 1.1 Setup mode

| Choice | Select |
| ------ | ------ |
| Setup mode | **2. Full setup** — configure providers and tools yourself |

### 1.2 Model provider

| Field | Value |
| ----- | ----- |
| Provider | **Custom / OpenAI-compatible** (`custom` direct API) |
| API base URL | `http://127.0.0.1:11434/v1` |
| API key | Leave blank |
| Compatibility mode | **1. Auto-detect** |

> **Why `127.0.0.1`?** Hermes talks to Ollama through the SSH tunnel (Step 2), which forwards your laptop's port 11434 to the Thor.

### 1.3 Model settings

| Field | Example value | Notes |
| ----- | ------------- | ----- |
| Model name | `gemma4:31b` | Must match a model on the Thor |
| Context length | `256000` | Match your model's limit |
| Display name | `sage-thor-H020-gemma4-31b` | Any label that helps you identify this endpoint |

### 1.4 Terminal & platforms

| Prompt | Select |
| ------ | ------ |
| Terminal backend | **Keep current (local)** |
| Platforms (Mattermost, Slack, etc.) | Skip — press **Enter** |

### 1.5 CLI tools

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

### 1.6 Provider choices

| Category | Select |
| -------- | ------ |
| Browser | **Local Browser** (recommended, free) |
| Text-to-Speech | **Microsoft Edge TTS** (free) |
| Web Search | **DuckDuckGo (ddgs)** (free, no API key) |

### 1.7 Finish install

You should see a setup summary and **Installation Complete**. Some tools may show as disabled until you add API keys later — that's expected.

Reload your shell and verify:

```bash
source ~/.zshrc   # or your shell config file
hermes --version
```

<details>
<summary>Full installer prompts (reference)</summary>

**Setup mode:**
```
(○) 1. Quick Setup (Nous Portal)
(●) 2. Full setup
(○) 3. Blank Slate
```

**Custom endpoint:**
```
API base URL: http://127.0.0.1:11434/v1
API key: <leave blank>
Choice [1-4]: 1   # Auto-detect
```

**Model:**
```
Model name: gemma4:31b
Context length: 256000
Display name: sage-thor-H020-gemma4-31b
```

**Expected completion output:**
```
┌─────────────────────────────────────────────────────────┐
│              ✓ Installation Complete!                   │
└─────────────────────────────────────────────────────────┘

   hermes              Start chatting
   hermes gateway      Start messaging gateway
   hermes doctor       Check for issues
```

</details>

---

## Step 2 — Open the SSH tunnel

Replace `username` and `thor-host` with your credentials:

```bash
ssh -L 11434:127.0.0.1:11434 username@thor-host
```

**Keep this terminal open** while using Hermes.

```
Laptop localhost:11434
        │
        │  SSH Tunnel
        ▼
Thor   localhost:11434
```

---

## Step 3 — Verify the connection

Open a **new terminal** on your laptop (leave the tunnel running).

**List models on the Thor:**

```bash
curl http://127.0.0.1:11434/api/tags
```

**Verify the OpenAI-compatible endpoint:**

```bash
curl http://127.0.0.1:11434/v1/models
```

If both return model data, Hermes can connect.

---

## Step 4 — Reconfigure later (optional)

Already set up? Add or change models anytime:

```bash
hermes model
```

First-time setup after install:

```bash
hermes setup
```

Use the same values from [Step 1](#step-1--install-hermes). Run `hermes model` again whenever you add another Thor endpoint.

---

## Step 5 — Launch Hermes

```bash
hermes
```

Hermes connects through the tunnel to Ollama on the Thor GPU. Local tools (files, terminal, browser) still run on your laptop.

---

## Troubleshooting (Thor)

| Check | Command |
| ----- | ------- |
| Tunnel active? | `curl http://127.0.0.1:11434/api/tags` |
| OpenAI endpoint? | `curl http://127.0.0.1:11434/v1/models` |
| Hermes health | `hermes doctor` |

**If Hermes can't connect:**

1. Confirm the SSH tunnel terminal is still open.
2. Confirm Ollama is running on the Thor.
3. Confirm the model name in Hermes matches a model from `/v1/models`.

To enable more tools later: `hermes setup tools` or edit `~/.hermes/.env`.

---

# Part 2: NVIDIA Hosted APIs

No Thor GPU required. Hermes talks to **NVIDIA Build** over HTTPS using an OpenAI-compatible API.

## At a glance

```
  Laptop                    NVIDIA Build
┌──────────────────┐        ┌──────────────────────────┐
│  Hermes Agent    │  HTTPS │  integrate.api.nvidia    │
│  Local files     │───────►│  Managed GPU inference   │
│  Local terminal  │  TLS   │  OpenAI-compatible API   │
└──────────────────┘        └──────────────────────────┘
```

No SSH tunnel. No Ollama. No GPU to manage.

---

## Prerequisites

- [ ] NVIDIA Developer account
- [ ] API key from [NVIDIA Build](https://build.nvidia.com/settings/api-keys)
- [ ] Hermes installed on your laptop ([Step 1 in Part 1](#step-1--install-hermes))

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

---

## Step 5 — Launch Hermes

```bash
hermes
```

All inference requests go to NVIDIA's hosted infrastructure.

---

## Troubleshooting (NVIDIA)

1. API key must start with `nvapi-`.
2. Base URL must be exactly `https://integrate.api.nvidia.com/v1`.
3. Model ID must match the catalog exactly.
4. On the free tier, high demand can cause occasional delays.

**References:** [NVIDIA NIM API](https://build.nvidia.com/) · [API Reference](https://docs.nvidia.com/nim/large-language-models/latest/api-reference.html) · [Forum — connection issues](https://forums.developer.nvidia.com/t/not-connect-to-endpoint-https-integrate-api-nvidia-com-v1/324036)

---

# Thor vs. NVIDIA Hosted APIs

| | Thor + Ollama | NVIDIA Hosted APIs |
| --- | --- | --- |
| **GPU** | Your Thor | None (managed by NVIDIA) |
| **Setup** | Medium | Low |
| **SSH tunnel** | Required | Not needed |
| **API key** | Not required | Required (`nvapi-...`) |
| **Internet** | Only for SSH | Always |
| **Models** | Any Ollama model you install | NVIDIA catalog only |
| **Cost** | Your GPU resources | NVIDIA Build credits |

**Choose Thor** when you have GPU access and want full model control.

**Choose NVIDIA** when you want the simplest path — Hermes locally, inference in the cloud.

# Switching between the two approaches

Once you set up Hermes with both approaches, you can switch between them relatively easily by running the following command:

```bash
hermes model
```

Then select the appropriate option from the list of providers. For example, if you want to switch to the NVIDIA Hosted APIs, you would select the **NVIDIA NIM** provider. If you want to switch to the Thor + Ollama approach, you would select the provider with the name you previously gave to the Thor + Ollama approach, so if you called it *sage-thor-H020-gemma4-31b*, you would select that provider.