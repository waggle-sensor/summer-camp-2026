# Hugging Face MCP Server

Connect Hermes to the Hugging Face Hub (models, datasets, Spaces, papers, docs, Jobs) via the official MCP server.

| | |
|--|--|
| **Docs** | <https://huggingface.co/docs/hub/en/agents-mcp> |
| **MCP settings (client snippet)** | <https://huggingface.co/settings/mcp> |
| **Remote endpoint** | `https://huggingface.co/mcp` |
| **Source** | <https://github.com/huggingface/hf-mcp-server> |
| **Server landing** | <https://huggingface.co/mcp> |

What it enables: search/explore Hub models, datasets, Spaces, and papers; semantic search over Hugging Face documentation; run/manage Hub Jobs; optionally call MCP-compatible Gradio Spaces as tools — all from Hermes instead of raw Hub API/`huggingface_hub` scripts.

Configure which built-in tools and community Spaces are exposed in [MCP settings](https://huggingface.co/settings/mcp) while logged in. Prefer the settings page snippet when wiring a desktop client; for Hermes use the remote URL + Bearer token below.

---

## Built-in tools (toggle in settings)

| Tool | Role |
|------|------|
| Spaces Semantic Search | Find AI apps / Spaces by natural language |
| Papers Semantic Search | Find ML papers |
| Model Search | Models with task/library filters |
| Dataset Search | Datasets with author/tag filters |
| Documentation Semantic Search | HF library docs (guides, API refs) |
| Run and Manage Jobs | Jobs on Hugging Face infrastructure |
| Hub Repository Details | Model/Dataset/Space metadata (optional README) |

Add community Gradio Spaces with MCP support from [spaces?filter=mcp-server](https://huggingface.co/spaces?filter=mcp-server) via the same settings page. Restart Hermes after changing tools/Spaces.

---

## Remote server (recommended on Thor)

Hosted by Hugging Face — no local Node/Docker required for the default path.

**Auth:** Hugging Face **access token** as `Authorization: Bearer <HF_TOKEN>`. Create at <https://huggingface.co/settings/tokens> (read scopes are enough for search; write/Jobs need broader scopes).

Never commit the token. Put it in the profile `.env` (user-owned, not in the distribution).

### Add with Hermes CLI

```bash
# Interactive — paste HF token when prompted for auth
hermes mcp add huggingface --url "https://huggingface.co/mcp"

# Verify
hermes mcp list
```

After adding, start a **new** Hermes session. Tools show up as `mcp_huggingface_*` (names vary by enabled tools).

### Equivalent config shape

```json
{
  "mcp_servers": {
    "huggingface": {
      "url": "https://huggingface.co/mcp",
      "headers": {
        "Authorization": "Bearer <HF_TOKEN>"
      },
      "enabled": true,
      "timeout": 120
    }
  }
}
```

Optional env names used in camp docs: `HF_TOKEN` or `HUGGINGFACE_HUB_TOKEN` — copy into the Bearer header; do not ship real tokens in git.

Some clients also support `https://huggingface.co/mcp?login` for OAuth-style login; Hermes on Thor should prefer Bearer token.

---

## Related: Hugging Face skills

This profile also vendors workflow skills from [huggingface/skills](https://github.com/huggingface/skills) (`hf-cli`, `huggingface-*`, …). Catalog: **`huggingface-skills-index.md`**. Use MCP for live Hub tool calls; use skills for CLI/training/Gradio procedures.

## Camp usage tips

1. Prefer Hugging Face MCP for **models / datasets / Spaces / papers / HF docs / Jobs**. Sage MCP stays for nodes/data/jobs; GitHub MCP for source control; Milvus helper for vector-client code.
2. Toggle tools on the [settings](https://huggingface.co/settings/mcp) page so the agent only sees what students need (fewer tools = clearer routing).
3. Enable **Documentation Semantic Search** when students ask “how do I … with transformers/PEFT?”
4. Re-auth / new session after changing MCP config (same quirk as Sage MCP).

## Security

- Tokens stay in `.env` / Hermes auth store — never in skills, job YAMLs, or `hermes-profile/`.
- Rotate tokens if exposed; revoke at <https://huggingface.co/settings/tokens>.
