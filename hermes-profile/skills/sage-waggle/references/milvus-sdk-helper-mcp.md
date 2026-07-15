# Milvus SDK Code Helper (MCP) — prefer **Milvus Lite**

Official Milvus MCP that steers generated code toward the **current** SDK (`MilvusClient`) instead of outdated ORM-style examples.

| | |
|--|--|
| **Docs (MCP)** | <https://milvus.io/docs/milvus-sdk-helper-mcp.md> |
| **Docs (Milvus Lite)** | <https://milvus.io/docs/milvus_lite.md> · [Quickstart](https://milvus.io/docs/quickstart.md) |
| **Remote endpoint** | `https://sdk.milvus.io/mcp/` |
| **Auth** | None |
| **Required header** | `Accept: text/event-stream` (Streamable HTTP / SSE) |

**Why use the MCP:** LLMs often emit deprecated Milvus ORM patterns. With this helper, agents write officially recommended `MilvusClient` code.

---

## Camp default: Milvus Lite (not full Milvus)

For summer-camp / Thor / laptop work, **prefer Milvus Lite** — embedded, file-backed, no Docker/K8s cluster.

| Prefer | Avoid unless user asks |
|--------|-------------------------|
| `pip install -U "pymilvus[milvus-lite]"` | Standing up Milvus Standalone/Distributed |
| `MilvusClient("./something.db")` | `uri="http://localhost:19530"` as the default |
| Local `.db` for demos, notebooks, small apps | Requiring Zilliz Cloud or a remote cluster first |

```python
from pymilvus import MilvusClient

# Milvus Lite — local file URI (camp default)
client = MilvusClient("./milvus_demo.db")
```

Same `MilvusClient` API later ports to Standalone / Distributed / Zilliz by changing URI (and token):

```python
# Only when the user needs a server / production deploy
client = MilvusClient(uri="http://localhost:19530", token="root:Milvus")
```

Lite docs: [Run Milvus Lite Locally](https://milvus.io/docs/milvus_lite.md).

---

## Hermes setup

Shipped in profile `mcp.json` as **`sdk-code-helper`** (enabled). If missing after an older install:

```bash
hermes mcp add sdk-code-helper --url "https://sdk.milvus.io/mcp/"
# Ensure Accept header is set to text/event-stream (see config below)
hermes mcp list
```

Start a **new** Hermes session after adding/changing MCP config.

### Config shape

```json
{
  "mcp_servers": {
    "sdk-code-helper": {
      "url": "https://sdk.milvus.io/mcp/",
      "headers": {
        "Accept": "text/event-stream"
      },
      "enabled": true,
      "timeout": 120
    }
  }
}
```

Same endpoint works in Cursor / Claude / VS Code / Windsurf — see the [MCP Quickstart](https://milvus.io/docs/milvus-sdk-helper-mcp.md).

---

## Agent tips

1. Default vector examples → **Milvus Lite** + local `.db` + `MilvusClient`.
2. Use this MCP so snippets stay on current APIs (not ORM).
3. Sage MCP = nodes/data/jobs; GitHub MCP = repos/PRs; **Milvus helper** = correct client code.
4. Do not invent a full Milvus server deploy for a simple embedding/search demo.

## Security

- Public remote helper — no token in `.env`.
- Keep any later cloud URI/token in user `.env`, never in skills or git.
