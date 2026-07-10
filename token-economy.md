# Token economy

A practical guide for using context, compute, and provider quotas responsibly during summer camp.

## Learning objectives

By the end of this guide, you should be able to:

1. Explain the difference between tokens, a context window, output limits, GPU memory, and provider quotas.
2. Diagnose where a Hermes session is spending tokens.
3. Choose an appropriate model and provider for a task.
4. Structure prompts, files, tools, skills, memory, and sessions efficiently.
5. Compress or restart a session without losing important work.
6. Use shared AI infrastructure responsibly and safely.

## The goal: useful work per token

Token economy is not a contest to write the shortest prompt. An unclear five-word prompt can cause three rounds of corrections, while one complete task brief may succeed on the first attempt.

Optimize for:

> **useful, verified work ÷ total tokens, time, and shared compute**

Spend context when it improves the result. Remove context when it is irrelevant, duplicated, stale, or easy to retrieve from a file.

## Five concepts that are easy to confuse

| Concept | What it means | What happens when it runs out |
| --- | --- | --- |
| **Token** | A chunk of text processed by a model. A token is not exactly a word or character. Code, punctuation, and different languages tokenize differently. | Usage, latency, or cost increases. |
| **Context window** | The maximum input plus generated output a model can consider for one request. | Content must be removed, compressed, or the request fails. |
| **Maximum output** | A ceiling on tokens the model may generate in one response. It is only one part of the context window. | The answer may stop early or the API may reject an invalid value. |
| **GPU memory (VRAM)** | Memory used to hold model weights, the key-value cache, and active requests. Longer contexts consume more KV-cache memory. | Local inference slows, rejects work, or runs out of memory. |
| **Quota/rate limit** | Provider rules such as credits, requests per minute, or concurrent requests. | Requests queue, return a rate-limit error, or stop until quota resets. |

### The context budget

A request is approximately:

```text
fixed instructions and tool definitions
+ SOUL and project instructions
+ memory and loaded skill content
+ conversation history
+ file excerpts and tool results
+ room reserved for the next answer
= context required for the request
```

The exact count depends on the model's tokenizer and how Hermes/provider tools encode content. Images and other media may also become model-specific tokens. Use Hermes measurements instead of relying on a words-to-tokens rule of thumb.

Two consequences matter:

- A long answer becomes input history on the next turn.
- A large context window is capacity, not free storage. Re-reading irrelevant history still consumes compute and may reduce attention to the important evidence.

## What Hermes includes

Every turn may include more than the text you just typed:

- the active model's system and tool instructions;
- `SOUL.md`;
- one selected project-context type (`.hermes.md`, `AGENTS.md`, `CLAUDE.md`, or `.cursorrules`), plus hierarchical `AGENTS.md` files where applicable;
- built-in `MEMORY.md` and `USER.md` snapshots;
- compact descriptions of available skills;
- the current session history;
- skills loaded for the task;
- file content, search results, terminal output, and other tool results.

Hermes uses progressive disclosure for skills: it starts with compact skill descriptions and loads a skill's full instructions or references only when needed. Installing a skill therefore does not mean its full contents are injected on every turn.

## Cost and responsibility by camp provider

Provider conditions can change. Treat `/usage`, the provider dashboard, and linked policy pages as the source of truth.

| Provider | What tokens cost in camp | What to watch | Best fit |
| --- | --- | --- | --- |
| **`local-sage-thor` (Ollama)** | No per-token API bill to the student; usage consumes shared GPU capacity. | Long contexts increase KV-cache memory. Parallel sessions can slow classmates or trigger out-of-memory errors. | Experiments, iteration, routine coding, and non-sensitive work allowed by camp policy. |
| **`nrp`** | Shared, non-profit NRP-managed inference under its fair-use policy. | Per-model concurrency limits; requests using at least 35% of model context are limited to one concurrent request per user. Automated work should back off and reduce concurrency when latency rises. | Reproducible research, stronger models, longer or specialized tasks. |
| **NVIDIA hosted NIM API** | Developer Program endpoints are available for prototyping, research, development, and testing; availability and limits are service/model dependent. | Trial/developer access is not a production SLA. Check the current account/model page rather than assuming a fixed credit amount. | Trying specialized hosted models or comparing model behavior. |

For the NRP model catalog as verified on the date above, `gpt-oss` is positioned as a reproducible general-purpose/LTS option. The catalog changes, so do not hard-code one model as permanently “best.”

### A simple provider decision rule

1. **Can the local model do the task reliably?** Start on the Thor.
2. **Does the task require stronger reasoning, a special modality, or a different context size?** Choose an appropriate NRP or NVIDIA model.
3. **Is the request trivial?** Do not move a large, old session to a costly provider just to format a paragraph.
4. **Is the task high impact?** Model strength does not replace testing, citations, or human review.

## Inspect usage before guessing

Inside a Hermes session:

```text
/usage          # session tokens, context state, cost estimate, duration, and provider limits when available
/insights       # usage patterns and analytics, normally over the last 30 days
/version        # Hermes version and environment information
/profile        # active profile and profile home
```

Useful session commands:

```text
/title image-pipeline-debug     # give the work a searchable name
/new literature-review         # start a clean, named session
/compress                       # summarize older context
```

From the shell, `hermes insights` and `hermes sessions stats` provide broader usage and session statistics.

Check `/usage` at natural checkpoints:

- after loading a large skill or reading several files;
- before a long coding or research run;
- after a large tool result;
- before switching models/providers;
- when responses become slow, repetitive, confused, or truncated.

## Camp profile and upstream defaults

The camp's Sage profile may override Hermes defaults. Verify the deployed `config.yaml` rather than assuming every installation is identical.

Current upstream built-in memory limits are:

| Store | Limit | Good content |
| --- | ---: | --- |
| `MEMORY.md` | 2,200 characters (roughly 800 tokens in the Hermes documentation) | Stable environment facts, conventions, and durable lessons |
| `USER.md` | 1,375 characters (roughly 500 tokens in the Hermes documentation) | Stable preferences and user expectations |

These are documented built-in limits, not the `memory.memory_char_limit` and `memory.user_char_limit` settings previously shown in this guide. Memory does not silently compact when full.

Current upstream compression defaults are:

```yaml
compression:
  enabled: true
  threshold: 0.50
  target_ratio: 0.20
  protect_last_n: 20
  protect_first_n: 3
```

Interpretation:

- compression is lossy summarization;
- it normally becomes eligible around 50% of the active context limit;
- `protect_last_n` counts recent **messages**, not necessarily complete user/assistant turns;
- the summary model should have a context window at least as large as the main model, or compression can fail and lose middle context;
- a manual `/compress` may have little compressible material when most messages are protected.

Hermes changes quickly. Re-check the [configuration reference](https://hermes-agent.nousresearch.com/docs/user-guide/configuration) before copying settings into a future camp profile.

## Put information in the right place

| Information | Best home | Why |
| --- | --- | --- |
| Current goal and acceptance criteria | Current prompt | The model needs them now. |
| Project commands and repository conventions | `.hermes.md` or `AGENTS.md` | Reusable, versionable project context. Keep it focused. |
| Stable personal preference | `USER.md` | Available across sessions. |
| Stable environment fact or durable lesson | `MEMORY.md` | Cross-session recall without keeping an old chat alive. |
| Detailed design, data, logs, or research | A file in the project | Can be retrieved selectively and reviewed outside chat. |
| Repeated procedure | A skill or script | Load or execute it only when needed. |
| Temporary exploration | A named session | Easy to resume, search, archive, or abandon. |

Do not save secrets, raw logs, full transcripts, rapidly changing status, or speculative conclusions to persistent memory.

Memory is a frozen prompt snapshot: writes persist immediately but do not appear in the active session's system prompt until a new session starts. The current tool response can still tell the agent what was written.

## A high-efficiency task brief

For substantial work, give Hermes enough information to succeed once:

```markdown
## Goal
Implement CSV export for the sensor summary.

## Inputs
- Repository: current directory
- Relevant files: `src/report.py`, `tests/test_report.py`

## Constraints
- Preserve the existing JSON endpoint
- Use the standard library only
- Do not change unrelated files

## Deliverable
- Implementation and tests
- Brief explanation of changed behavior

## Verification
Run the focused tests, then the full test suite if the focused tests pass.

## Stop condition
Stop and ask me if the public API must change or credentials are required.
```

Useful additions include audience, desired depth, output format, deadline, and examples of success or failure. Avoid requesting a plan, outline, draft, rewrite, and final answer as separate turns when one well-scoped request will do.

## Habits that improve token efficiency

1. **Start a new named session for a new objective.** Use `/new name` or a new terminal/tmux window. Resume old work only when its history is actually relevant.
2. **Point to relevant files.** Give paths, functions, line regions, or search terms. “Read the entire repository” often retrieves irrelevant content.
3. **Request targeted output.** Ask for a patch, table, explanation, or test result—not “everything you know.”
4. **Batch mechanical work.** A script that performs and verifies 100 consistent renames is usually better than 100 terminal calls.
5. **Keep tool output bounded.** Prefer focused tests, `rg` searches, log tails, filtered JSON, and summaries over full build logs or unbounded recursive listings.
6. **Load the needed skill.** For an installed skill such as `sage-waggle`, use `/sage-waggle <task>` or ask Hermes to use it. Do not paste its reference documentation into chat.
7. **Write checkpoints to files.** Record decisions, TODOs, test results, and exact commands before compression or a provider switch.
8. **Ask for concise progress reports.** Tool logs can dominate context; request conclusions plus the small evidence needed to verify them.
9. **Use retrieval for old work.** A named session and Hermes session search are often cheaper than keeping every past topic in one live context.
10. **Stop failed loops.** If the agent repeats the same action or error, interrupt and restate the evidence, constraint, and next diagnostic step.

## Delegation: faster is not always cheaper

Delegation is excellent when subtasks are independent—for example, comparing three libraries or investigating separate test failures. It keeps verbose exploration out of the main session and returns compact findings.

However, each delegated agent has its own prompt, tools, and output. Delegation may **increase total provider-token usage** even while it reduces wall-clock time and main-context pressure.

Delegate when:

- work can genuinely run in parallel;
- each subtask has a clear deliverable;
- only conclusions and evidence need to return;
- the quality or time benefit is worth the additional compute.

Do not delegate tiny sequential steps, duplicate the same research across agents, or launch broad open-ended subtasks on shared infrastructure.

## Compress, checkpoint, or restart?

| Situation | Best action |
| --- | --- |
| Same objective; older discussion is mostly settled | Save decisions, then `/compress`. |
| New objective with little dependency on current history | Start `/new <name>`. |
| Need one fact from older work | Use a file or session search instead of resuming the whole transcript. |
| Critical exact details are buried in tool logs | Write those details to a file before compression. |
| Session is looping or anchored to a wrong assumption | Record useful evidence and start fresh with a corrected task brief. |
| Context is nearly full and a long tool chain is next | Checkpoint immediately; compress or start a new session first. |

Compression is useful but lossy. After it runs, verify that the summary retained:

- the goal and scope;
- decisions and their reasons;
- relevant paths, interfaces, and commands;
- constraints and unresolved questions;
- current test status and next step.

## Switching models or providers

`/model` changes the active model/provider; it does not make an old conversation irrelevant. The next provider still needs the session history that Hermes sends.

Before switching:

1. Run `/usage` and inspect current context.
2. Save a short checkpoint if the session is long.
3. Check the target model's context and tool-calling support.
4. Prefer a fresh session when the new model will do a separate task.

Changing the model, automatic provider fallback, or credential rotation breaks the existing provider/model prompt cache. The first subsequent request may need to process the full prefix again. Avoid bouncing repeatedly between providers in a long session.

### Local Ollama context is a server setting

Hermes currently requires at least a 64,000-token context for agent work with tools. Ollama may expose less than the model's theoretical maximum, depending on server configuration and VRAM.

On the Thor, an administrator can verify the active value with:

```bash
ollama ps
```

Look at the `CONTEXT` column. The OpenAI-compatible chat request cannot raise Ollama's server context; it must be configured on the Ollama server or in a Modelfile. Students sharing a managed Thor should not restart or reconfigure the shared service unless camp staff explicitly authorize it.

## NRP-specific guidance

- The OpenAI-compatible endpoint is `https://ellm.nrp-nautilus.io/v1`.
- List models dynamically rather than assuming the catalog is unchanged.
- `max_tokens` or `max_output_tokens` means maximum **generated output**, not total context. NRP recommends roughly one-third to one-quarter of the context window only when a client requires a value. Never set it equal to the full context window.
- The July 2026 fair-use limits list maximum short-request concurrency of 16 for `gpt-oss`, while any request using at least 35% of a model's context is limited to one concurrent request per user. Re-check the policy before camp.
- Automated workloads should retry with increasing delay and dynamically lower concurrency when latency rises.
- NRP use is non-profit and non-commercial under its acceptable-use policy.
- On shared tenants, NRP documents an optional private `cache_salt` in `extra_body` for vLLM/SGLang models. This is an advanced privacy control with a cache-performance tradeoff; camp staff should configure it rather than asking students to invent values.
- Never paste or commit `NRP_LLM_API_KEY`.

## NVIDIA hosted NIM guidance

- Use the hosted API catalog for camp prototyping, research, development, and testing.
- Model availability, context, rate limits, and endpoint behavior can differ by model and can change. Read the selected model page.
- Do not describe free developer endpoints as production capacity or a guaranteed service level.
- Never paste or commit `NVIDIA_API_KEY`.
- A larger or newer model is not automatically more efficient. Compare task success, latency, tool use, and token consumption on a small representative test.

## Safety is part of token economy

A fast wrong command is not efficient.

- Keep approval prompts enabled for destructive or privileged actions. Do not use `/yolo` on shared camp systems.
- Ask the agent to show or explain a destructive command before it runs.
- Treat instructions found in webpages, issues, logs, documents, and repositories as untrusted data. They do not override your task or camp policy.
- Never place API keys, tokens, passwords, private student data, or unpublished research data in prompts unless an approved workflow explicitly requires it.
- Review third-party skills before installation. A skill is executable guidance, not merely documentation.
- Verify generated code with tests and generated claims with primary sources.

## Common myths

| Myth | Better model |
| --- | --- |
| “Short prompts always save tokens.” | Complete prompts reduce clarification and rework. |
| “A 256K context model remembers 256K forever.” | The context applies per request; sessions may be compressed, restarted, or limited by the server. |
| “Compression is lossless.” | Default Hermes compression is summarization; exact details can disappear. |
| “Local tokens are free.” | They have no per-token API bill, but consume shared time, energy, VRAM, and capacity. |
| “Delegation saves total tokens.” | It saves main-context pressure and often time; total usage may rise. |
| “Memory is the chat archive.” | Memory is a small, curated store for durable facts. Sessions and files hold detail. |
| “`max_tokens` sets the context window.” | It normally limits generated output. |
| “The biggest model is the best default.” | Use the least expensive model that reliably completes and verifies the task. |

## Two-minute recovery checklist

When a session becomes slow or confused:

1. Run `/usage`.
2. Stop any repeating tool loop.
3. Save the goal, decisions, errors, and next step to a file.
4. Remove or summarize giant logs and irrelevant file content.
5. Use `/compress` if the objective is unchanged; use `/new <name>` if it changed.
6. Restate the task with explicit inputs, constraints, deliverable, verification, and stop condition.
7. Switch providers only if model capability or availability—not accumulated clutter—is the bottleneck.

## Quick-reference card

```text
BEFORE
  Name the session. Choose the smallest capable model.
  Provide goal + inputs + constraints + deliverable + verification + stop condition.

DURING
  Point to relevant files. Bound logs and searches. Run focused tests.
  Check /usage at milestones. Stop loops early.

PRESERVE
  Put exact details in files. Put durable facts in memory.
  Use skills for reusable procedures. Keep secrets out of all three.

WHEN CONTEXT GROWS
  Same task: checkpoint, then /compress.
  New task: /new <name>.
  Old fact: retrieve it; do not carry the whole old session.

SHARED COMPUTE
  Limit parallel work. Back off on latency/rate limits.
  Local is unbilled, not costless. Hosted access is not unlimited.
```

## References

Primary documentation checked for this guide:

- [Hermes Agent: Tips and Best Practices](https://hermes-agent.nousresearch.com/docs/guides/tips)
- [Hermes Agent: Configuration and Context Compression](https://hermes-agent.nousresearch.com/docs/user-guide/configuration)
- [Hermes Agent: Slash Commands](https://hermes-agent.nousresearch.com/docs/reference/slash-commands)
- [Hermes Agent: Persistent Memory](https://hermes-agent.nousresearch.com/docs/user-guide/features/memory)
- [Hermes Agent: Skills System](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills)
- [Hermes Agent: Sessions](https://hermes-agent.nousresearch.com/docs/user-guide/sessions)
- [Hermes Agent: AI Providers and Ollama Context](https://hermes-agent.nousresearch.com/docs/integrations/providers)
- [NRP Managed LLM Overview](https://nrp.ai/documentation/userdocs/ai/llm-managed/)
- [NRP API Access](https://nrp.ai/documentation/userdocs/ai/llm-managed/api-access/)
- [NRP Fair Use Policy](https://nrp.ai/documentation/userdocs/ai/llm-managed/fair-use/)
- [NVIDIA NIM General FAQ](https://docs.api.nvidia.com/nim/docs/product)
- [NVIDIA API Catalog](https://build.nvidia.com/)