## graphify

This profile **requires** a knowledge graph at `graphify-out/` over `skills/` + `docs/` (god nodes, communities, cross-file relationships).

When the user types `/graphify`, use the bundled **`graphify`** skill before doing anything else.

### Camp rule — discover skills and docs through the graph

This Hermes profile ships a large skill/doc corpus (Sage/Waggle, Hugging Face, NVIDIA Jetson, …). **Do not** mass-read the skills tree to find which skill or reference to use.

Rules:
- For any question about **which skill, which reference, which doc, architecture, or how things connect** in this profile: first run `graphify query "<question>"` when `graphify-out/graph.json` exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts.
- **CWD is usually `$HOME` (e.g. `/root`), not the profile.** Never assume `scripts/setup-graphify.sh` exists in the current directory.
- If `graphify-out/graph.json` is **missing** (check under the profile root, not `$HOME`):
  1. Tell the user setup takes a **long time** (often 30+ minutes on Thor; can be hours) — do **not** run extract in a blocking/foreground tool that will timeout.
  2. Resolve the setup script with an **absolute path**, then run it **once** (background by default):

```bash
# Prefer installed profile, then common clone locations:
SETUP=""
for d in \
  "${HERMES_HOME:-$HOME/.hermes}/profiles/sage" \
  "$HOME/.hermes/profiles/sage" \
  "$HOME/summer-camp-2026/hermes-profile" \
  /root/summer-camp-2026/hermes-profile
 do
  if [ -f "$d/scripts/setup-graphify.sh" ]; then SETUP="$d/scripts/setup-graphify.sh"; break; fi
done
# Last resort:
[ -z "$SETUP" ] && SETUP="$(find "$HOME" -path '*/hermes-profile/scripts/setup-graphify.sh' 2>/dev/null | head -1)"
[ -n "$SETUP" ] || { echo "setup-graphify.sh not found"; exit 1; }
bash "$SETUP"           # backgrounds; returns immediately
bash "$SETUP" --status
```

  3. Ready when `"$(dirname "$SETUP")/../graphify-out/graph.json"` exists (i.e. profile `graphify-out/graph.json`). Follow with `tail -f "$(dirname "$SETUP")/../graphify-out/setup.log"`.
  4. Do **not** re-run setup in a loop waiting in the foreground; continue other work or poll `--status`.
  5. Do **not** use a relative `bash scripts/setup-graphify.sh` unless you have already `cd`'d into the profile root (`…/hermes-profile` or `~/.hermes/profiles/sage`).
- Dirty `graphify-out/` files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip if the task is about stale/incorrect graph output, or the user explicitly says not to use it.
- If `graphify-out/wiki/index.md` exists, use it for broad navigation instead of raw source browsing.
- Read `graphify-out/GRAPH_REPORT.md` only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying profile skill/doc files in this session, run `graphify update .` from the **profile root** to keep the graph current (AST-only, no API cost).
- Then load the **named** skill (`/skill sage-waggle`, `/skill jetson-llm-serve`, …) and follow it. Graphify finds; the skill teaches procedures.
- Still use Sage MCP for live nodes/data/jobs; Graphify does not replace MCP.

Camp setup: `references/graphify-guide.md` (in `sage-waggle`) and `scripts/setup-graphify.sh`.
