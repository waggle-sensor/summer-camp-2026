# Graphify — required skills/docs discovery for this profile

[Graphify](https://github.com/Graphify-Labs/graphify) is **required** on this Hermes profile. The profile ships ~250 skills and ~1.8K markdown files; the agent must discover the right skill/ref via the knowledge graph, not by grepping the tree.

| | |
|--|--|
| **Upstream** | <https://github.com/Graphify-Labs/graphify> |
| **Bundled skill** | `skills/graphify/` (Hermes/claw skill bundle) |
| **Always-on rules** | profile `AGENTS.md` |
| **Setup script** | `scripts/setup-graphify.sh` (venv + pip + Ollama `/v1`) |
| **Corpus** | `skills/` + `docs/` (see `.graphifyignore`) |
| **PyPI** | `graphifyy` (CLI: `graphify`) |
| **Venv** | `.venv-graphify/` (created by the setup script) |

## Agent protocol (non-negotiable)

1. If `graphify-out/graph.json` exists → `graphify query` / `path` / `explain` **before** mass-reading skills.
2. If the graph is missing → run `scripts/setup-graphify.sh` (**background by default** — long Thor job; use `--status` / wait for `graphify-out/graph.json`). Do not block foreground tools on extract.
3. Load the **specific** skill the graph points to (`sage-waggle`, `jetson-llm-serve`, `hf-cli`, …).
4. Use Sage / HF MCP for live data; Graphify indexes **this profile’s** skills and docs only.

Complementary routers: `nvidia-skill-finder`, `huggingface-skills-index.md`, `nvidia-skills-index.md` — still prefer the graph first when unsure.

## Install + build (every Thor / every profile install)

After `hermes profile install ./hermes-profile --name sage --alias`:

```bash
cd ~/.hermes/profiles/sage   # or the cloned hermes-profile/

chmod +x scripts/setup-graphify.sh
./scripts/setup-graphify.sh          # BACKGROUND by default (returns immediately)
./scripts/setup-graphify.sh --status # pid / log / ready?
# tail -f graphify-out/setup.log
```

Foreground only if you intentionally want to watch the whole run:

```bash
./scripts/setup-graphify.sh --foreground
```

The script:

1. **Defaults to background** (`nohup`) — extract often takes 30+ minutes on Thor and will timeout agent tools if run in the foreground
2. Creates `.venv-graphify` (avoids PEP 668 `externally-managed-environment`)
3. `pip install 'graphifyy[ollama]'` into that venv
4. Forces `OLLAMA_BASE_URL=…/v1` (OpenAI-compat — see troubleshooting)
5. Probes `/api/tags` and `/v1/chat/completions` before a long extract
6. Writes `graphify-out/setup.log` + `setup.pid`
Manual equivalent:

```bash
cd /path/to/hermes-profile
python3 -m venv .venv-graphify
source .venv-graphify/bin/activate
pip install --upgrade 'graphifyy[ollama]'

# CRITICAL: must end with /v1 — graphify uses the OpenAI client
export OLLAMA_BASE_URL=http://127.0.0.1:11434/v1
export OLLAMA_MODEL=gemma4:31b          # exact tag from `ollama list`
export OLLAMA_API_KEY=ollama            # any non-empty string; Ollama ignores auth
export GRAPHIFY_OLLAMA_KEEP_ALIVE=0
# Leave GRAPHIFY_OLLAMA_NUM_CTX unset (auto). Do not force 8192 — truncates big chunks.
graphify extract . --backend ollama --token-budget 25000 --max-concurrency 1 --api-timeout 1800
```

### `GRAPHIFY_OLLAMA_NUM_CTX` smaller than chunk (~57k) warning

If extract logs that `NUM_CTX` is below estimated chunk input, prompts are truncated and the graph can be empty/hollow.

- **Camp fix:** do not set `GRAPHIFY_OLLAMA_NUM_CTX` (let graphify auto-size) and use `--token-budget 25000` (default in `setup-graphify.sh`).
- **Low-VRAM only:** pair a small ctx with a matching budget, e.g. `GRAPHIFY_OLLAMA_NUM_CTX=16384 GRAPHIFY_TOKEN_BUDGET=4000`.
- If a background run started under the old `NUM_CTX=8192` default, **stop it and re-run** `./scripts/setup-graphify.sh` after pulling this fix.

Outputs:

```text
graphify-out/
├── graph.html
├── GRAPH_REPORT.md
└── graph.json
```

Rebuild after `hermes profile update sage`. Prefer `.venv-graphify/bin/graphify` (or `source .venv-graphify/bin/activate`).

**Expect:** Markdown semantic extract over ~1.8K files is slow and shares VRAM with Ollama chat. Instructors should pre-run `./scripts/setup-graphify.sh` on fleet images when possible so `graphify-out/` is warm.

## Troubleshooting

### `externally-managed-environment` (PEP 668)

Do **not** `pip install` into system Python. Use the script (creates `.venv-graphify`) or the venv steps above.

### HTTP 404 on every semantic chunk (`404 page not found`)

**Usual cause:** `OLLAMA_BASE_URL` is missing `/v1`.

`graphify --backend ollama` talks to Ollama through the **OpenAI-compatible** API (`/v1/chat/completions`), not bare `/api/chat`.

| URL | What gets called | Result |
|-----|------------------|--------|
| `http://127.0.0.1:11434/v1` | `/v1/chat/completions` | Correct |
| `http://127.0.0.1:11434` | `/chat/completions` | **404 page not found** |

Quick probe:

```bash
export OLLAMA_BASE_URL=http://127.0.0.1:11434/v1
export OLLAMA_API_KEY=ollama
export OLLAMA_MODEL=gemma4:31b   # from `ollama list`

curl -s "$OLLAMA_BASE_URL/models" -H "Authorization: Bearer $OLLAMA_API_KEY" | head
curl -s -o /tmp/out.json -w "%{http_code}\n" -X POST "$OLLAMA_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $OLLAMA_API_KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"$OLLAMA_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":8}"
cat /tmp/out.json
```

Expect HTTP **200**. If the body says `model … not found`, fix `OLLAMA_MODEL` to match `ollama list` exactly (another common 404).

Native API remaining healthy (`curl http://127.0.0.1:11434/api/tags`) does **not** prove the OpenAI-compat path works — you must probe `/v1/...`.

## Query examples

```bash
source .venv-graphify/bin/activate
graphify query "pluginctl sideload ECR acpi" --graph graphify-out/graph.json
graphify path "sage-waggle" "jetson-llm-serve" --graph graphify-out/graph.json
graphify explain "pywaggle upload_file" --graph graphify-out/graph.json
```

Optional MCP:

```bash
source .venv-graphify/bin/activate
python -m graphify.serve graphify-out/graph.json
```

## Security

Do not put secrets into `skills/` / `docs/` before extracting. Profile `.env` stays user-owned and outside the graph corpus.
