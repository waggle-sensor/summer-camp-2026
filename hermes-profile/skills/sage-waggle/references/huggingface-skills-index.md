# Hugging Face Skills (vendored)

Catalog of agent skills copied from [huggingface/skills](https://github.com/huggingface/skills) into this profile’s `skills/` tree. Attribution + commit pin: `skills/_vendor/huggingface-skills-SOURCE.md` (Apache-2.0).

Prefer **`hf-cli`** as the bootstrap skill for Hub operations. Pair Hub search/docs/Jobs with the Hugging Face **MCP** (`https://huggingface.co/mcp`) — see `huggingface-mcp-server.md`.

Invoke with `/skill <name>` or `hermes -s <name>` (exact names below).

## Camp-priority skills

| Skill | When to use |
|-------|-------------|
| **`hf-cli`** | Hub CLI (`hf`): download/upload models & datasets, Spaces, buckets, Jobs, auth, cache |
| **`hf-mcp`** | Guidance for HF MCP tools (models/datasets/Spaces/papers/docs/Jobs) once MCP is enabled |
| **`hf-mem`** | Estimate VRAM/RAM to load Safetensors or GGUF weights |
| **`huggingface-best`** | Recommend / compare models for a task |
| **`huggingface-local-models`** | Local llama.cpp / GGUF on CPU, Metal, CUDA, ROCm (Thor-relevant) |
| **`huggingface-datasets`** | Dataset Viewer API: splits, rows, filters, parquet |
| **`huggingface-spaces`** / **`huggingface-gradio`** / **`huggingface-zerogpu`** | Build/deploy demos on Spaces / Gradio / ZeroGPU |
| **`huggingface-llm-trainer`** / **`trl-training`** / **`huggingface-vision-trainer`** | Train/fine-tune on HF Jobs or TRL |
| **`train-sentence-transformers`** | Sentence / cross / sparse encoder training |
| **`huggingface-papers`** / **`huggingface-paper-publisher`** | Read / publish Hub paper pages |

Sage/Waggle edge work still uses **`sage-waggle`** — do not replace it with HF skills.

## Full inventory

| Name | Description |
|------|-------------|
| `hf-cli` | Hugging Face Hub CLI (`hf`) for models, datasets, spaces, buckets, repos, papers, jobs |
| `hf-mcp` | Use Hugging Face Hub via MCP server tools |
| `hf-mem` | Estimate memory to load Safetensors or GGUF weights for inference |
| `huggingface-best` | Find the best / recommended model for a task; compare by benchmarks |
| `huggingface-community-evals` | Local Hub model evals with inspect-ai / lighteval |
| `huggingface-datasets` | Dataset Viewer API (metadata, rows, search, parquet) |
| `huggingface-gradio` | Build Gradio web UIs and demos |
| `huggingface-llm-trainer` | Train/fine-tune with TRL or Unsloth on HF Jobs |
| `huggingface-local-models` | Local llama.cpp / GGUF selection and serving |
| `huggingface-lora-space-builder` | Gradio Space demos for a user LoRA |
| `huggingface-paper-publisher` | Publish and manage research papers on the Hub |
| `huggingface-papers` | Look up Hub paper pages and papers API metadata |
| `huggingface-spaces` | Build/deploy/maintain Hugging Face Spaces |
| `huggingface-tool-builder` | Scripts/tools that call the Hugging Face API |
| `huggingface-trackio` | Track/visualize training with Trackio |
| `huggingface-vision-trainer` | Vision train/fine-tune (detection, classification, SAM) on HF Jobs |
| `huggingface-zerogpu` | ZeroGPU / `@spaces.GPU` guidance for Spaces |
| `train-sentence-transformers` | SentenceTransformer / CrossEncoder / SparseEncoder training |
| `transformers-js` | Transformers.js in JS/TypeScript (WebGPU/WASM) |
| `trl-training` | TRL fine-tuning (SFT, DPO, GRPO, …) |
| `hf-cloud-aws-context-discovery` | Discover local AWS profile/region/account (SageMaker path) |
| `hf-cloud-python-env-setup` | Isolated Python env for SageMaker / AWS work |
| `hf-cloud-sagemaker-deployment-planner` | Plan model deployment to Amazon SageMaker AI |
| `hf-cloud-sagemaker-iam-preflight` | SageMaker execution role preflight |
| `hf-cloud-sagemaker-production-defaults` | SageMaker endpoints with production defaults |
| `hf-cloud-serving-image-selection` | Pick SageMaker serving container image URI |

AWS / SageMaker `hf-cloud-*` skills are included for completeness; camp default remains Thor + Ollama / local HF workflows, not AWS.

## Re-sync from upstream

See `skills/_vendor/huggingface-skills-SOURCE.md`. After re-copying, bump `distribution.yaml` version and mention the new upstream commit in release notes.
