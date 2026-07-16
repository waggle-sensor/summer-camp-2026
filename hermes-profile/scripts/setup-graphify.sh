#!/usr/bin/env bash
# Required camp setup: venv + pip install Graphify + build skills/docs graph.
#
# Uses the same LLM as Hermes when possible: reads profile config.yaml (+ .env)
# for model / base_url / API key, then picks Graphify --backend ollama|openai.
#
# DEFAULT: runs the long extract in the BACKGROUND (nohup) and returns immediately.
#   ./scripts/setup-graphify.sh              # start background job
#   ./scripts/setup-graphify.sh --status     # pid / log / graph ready?
#   ./scripts/setup-graphify.sh --stop       # kill background job
#   ./scripts/setup-graphify.sh --foreground # block until done (manual / CI)
#
# Why background by default: semantic extract over ~1.8K markdown files takes
# many minutes on Thor and will timeout Hermes/agent foreground tools.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/$(basename "${BASH_SOURCE[0]:-$0}")"
cd "$ROOT"

mkdir -p graphify-out
LOG="${GRAPHIFY_SETUP_LOG:-$ROOT/graphify-out/setup.log}"
PIDFILE="${GRAPHIFY_SETUP_PIDFILE:-$ROOT/graphify-out/setup.pid}"
GRAPH_JSON="$ROOT/graphify-out/graph.json"

_cmd="${1:-}"

_pid_alive() {
  local pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

_status() {
  echo "Profile root: $ROOT"
  if [ -f "$PIDFILE" ]; then
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if _pid_alive "$pid"; then
      echo "Status: RUNNING (pid $pid)"
      echo "Log:    $LOG  (tail -f \"$LOG\")"
      return 0
    fi
    echo "Status: idle (stale pidfile pid=${pid:-empty})"
  else
    echo "Status: idle (no background job)"
  fi
  if [ -f "$GRAPH_JSON" ]; then
    echo "Graph:  READY ($GRAPH_JSON)"
    ls -l "$GRAPH_JSON" || true
  else
    echo "Graph:  NOT READY (missing $GRAPH_JSON)"
  fi
  if [ -f "$LOG" ]; then
    echo "---- last 15 log lines ----"
    tail -n 15 "$LOG" || true
  fi
}

_stop() {
  if [ ! -f "$PIDFILE" ]; then
    echo "No pidfile at $PIDFILE"
    exit 0
  fi
  local pid
  pid="$(cat "$PIDFILE")"
  if _pid_alive "$pid"; then
    echo "Stopping pid $pid ..."
    kill "$pid" 2>/dev/null || true
    sleep 1
    _pid_alive "$pid" && kill -9 "$pid" 2>/dev/null || true
    echo "Stopped."
  else
    echo "Process $pid not running."
  fi
  rm -f "$PIDFILE"
}

# Load KEY=VALUE from profile .env without executing shell in the file.
_load_dotenv() {
  local envfile="$1"
  [ -f "$envfile" ] || return 0
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == export\ * ]] && line="${line#export }"
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    key="${key#"${key%%[![:space:]]*}"}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    # Strip optional surrounding quotes
    if [[ "$val" == \"*\" ]]; then val="${val:1:${#val}-2}"; fi
    if [[ "$val" == \'*\' ]]; then val="${val:1:${#val}-2}"; fi
    # Do not clobber non-empty caller env; empty → allow .env to fill
    if [ -z "${!key:-}" ]; then
      export "$key=$val"
    fi
  done <"$envfile"
}

# Resolve Hermes model.default / base_url / key_env from config.yaml → shell vars.
# Outputs: HERMES_MODEL HERMES_BASE_URL HERMES_KEY_ENV HERMES_PROVIDER HERMES_PROVIDER_NAME
_resolve_hermes_model() {
  local cfg="${1:-$ROOT/config.yaml}"
  local helper
  helper="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/_resolve_hermes_model.py"
  HERMES_MODEL=""
  HERMES_BASE_URL=""
  HERMES_KEY_ENV=""
  HERMES_PROVIDER=""
  HERMES_PROVIDER_NAME=""
  [ -f "$cfg" ] || return 0
  [ -f "$helper" ] || {
    echo "WARNING: missing $helper — falling back to Ollama defaults" >&2
    return 0
  }
  # shellcheck disable=SC1090
  eval "$(python3 "$helper" "$cfg")"
}

_ensure_v1() {
  local url="${1%/}"
  case "$url" in
    */v1) echo "$url" ;;
    *) echo "${url}/v1" ;;
  esac
}

_is_ollama_url() {
  local url="$1"
  case "$url" in
    *11434*|*:11434/*|*localhost:11434*|*127.0.0.1:11434*) return 0 ;;
  esac
  return 1
}

case "$_cmd" in
  --status|-s) _status; exit 0 ;;
  --stop) _stop; exit 0 ;;
  --help|-h)
    cat <<'EOF'
Usage: setup-graphify.sh [--status|--stop|--foreground]

  (default)     Start extract in BACKGROUND; print pid/log and exit 0 quickly.
  --foreground  Run install+extract in this terminal (blocks for a long time).
  --status      Show running job / graph readiness / recent log.
  --stop        Kill background setup job.

LLM selection (Hermes-aligned):
  Reads profile config.yaml model.default / model.base_url (+ custom_providers)
  and profile .env for API keys. Ollama URLs → --backend ollama; otherwise
  OpenAI-compatible (NRP, NVIDIA Build, …) → --backend openai.

Env overrides (always win over config.yaml):
  GRAPHIFY_BACKEND=ollama|openai
  OLLAMA_BASE_URL / OLLAMA_MODEL / OLLAMA_API_KEY
  OPENAI_BASE_URL / OPENAI_MODEL / OPENAI_API_KEY
  GRAPHIFY_TOKEN_BUDGET (default 25000), GRAPHIFY_MAX_CONCURRENCY (default 1),
  GRAPHIFY_API_TIMEOUT (default 1800s), GRAPHIFY_FOREGROUND=1, GRAPHIFY_VENV,
  GRAPHIFY_OLLAMA_NUM_CTX
EOF
    exit 0
    ;;
esac

# ── Default: background the long job ─────────────────────────────────────────
_want_fg=0
if [ "$_cmd" = "--foreground" ] || [ "${GRAPHIFY_FOREGROUND:-}" = "1" ]; then
  _want_fg=1
fi

if [ "$_want_fg" -eq 0 ]; then
  if [ -f "$PIDFILE" ]; then
    _old="$(cat "$PIDFILE" 2>/dev/null || true)"
    if _pid_alive "$_old"; then
      echo "Graphify setup ALREADY RUNNING (pid $_old)."
      echo "  Log:    $LOG"
      echo "  Status: $SELF --status"
      exit 0
    fi
    rm -f "$PIDFILE"
  fi

  cat <<EOF
========================================================================
Graphify setup takes a LONG time on Thor (often 30+ minutes; can be hours).
Starting in the BACKGROUND so agent/tool timeouts are not hit.
  Log:  $LOG
  When ready: test -f graphify-out/graph.json
  Check: $SELF --status
========================================================================
EOF

  # Preserve useful env into the child (including Hermes API keys if already set)
  nohup env \
    GRAPHIFY_BACKEND="${GRAPHIFY_BACKEND:-}" \
    OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-}" \
    OLLAMA_MODEL="${OLLAMA_MODEL:-}" \
    OLLAMA_API_KEY="${OLLAMA_API_KEY:-}" \
    OPENAI_BASE_URL="${OPENAI_BASE_URL:-}" \
    OPENAI_MODEL="${OPENAI_MODEL:-}" \
    OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
    NRP_LLM_API_KEY="${NRP_LLM_API_KEY:-}" \
    NVIDIA_API_KEY="${NVIDIA_API_KEY:-}" \
    GRAPHIFY_TOKEN_BUDGET="${GRAPHIFY_TOKEN_BUDGET:-}" \
    GRAPHIFY_MAX_CONCURRENCY="${GRAPHIFY_MAX_CONCURRENCY:-}" \
    GRAPHIFY_API_TIMEOUT="${GRAPHIFY_API_TIMEOUT:-}" \
    GRAPHIFY_OLLAMA_NUM_CTX="${GRAPHIFY_OLLAMA_NUM_CTX:-}" \
    GRAPHIFY_OLLAMA_KEEP_ALIVE="${GRAPHIFY_OLLAMA_KEEP_ALIVE:-}" \
    GRAPHIFY_VENV="${GRAPHIFY_VENV:-}" \
    GRAPHIFY_FOREGROUND=1 \
    "$SELF" --foreground >>"$LOG" 2>&1 &
  echo $! >"$PIDFILE"
  echo "Started background pid $(cat "$PIDFILE")"
  echo "Follow: tail -f \"$LOG\""
  exit 0
fi

# ── Foreground worker (also used by the backgrounded child) ──────────────────
echo "==> [$(date -Is)] Profile root: $ROOT (foreground extract)"
echo "==> NOTE: full skills/docs semantic extract is slow — do not expect a quick finish."

_load_dotenv "$ROOT/.env"
# Also accept keys from parent Hermes home if profile .env lacks them
if [ -n "${HERMES_HOME:-}" ]; then
  _load_dotenv "${HERMES_HOME}/.env"
elif [ -f "$HOME/.hermes/.env" ]; then
  _load_dotenv "$HOME/.hermes/.env"
fi

PYTHON="${PYTHON:-python3}"
if ! command -v "$PYTHON" >/dev/null 2>&1; then
  echo "ERROR: $PYTHON not found. Install Python 3.10+ and retry." >&2
  exit 1
fi

VENV="${GRAPHIFY_VENV:-$ROOT/.venv-graphify}"
if [ ! -x "$VENV/bin/python" ]; then
  echo "==> Creating venv at $VENV (avoids externally-managed-environment / PEP 668)..."
  "$PYTHON" -m venv "$VENV"
fi
# shellcheck disable=SC1091
source "$VENV/bin/activate"
PY="$VENV/bin/python"
PIP="$VENV/bin/pip"
GRAPHIFY="$VENV/bin/graphify"

echo "==> Installing graphifyy[ollama] into $VENV ..."
"$PIP" install --upgrade pip
"$PIP" install --upgrade 'graphifyy[ollama]'

if [ ! -x "$GRAPHIFY" ]; then
  echo "ERROR: $GRAPHIFY missing after pip install." >&2
  exit 1
fi

"$PY" -c 'import sys; print(sys.executable)' > graphify-out/.graphify_python

_resolve_hermes_model "$ROOT/config.yaml"
echo "==> Hermes config: model=${HERMES_MODEL:-?} provider=${HERMES_PROVIDER:-?} name=${HERMES_PROVIDER_NAME:-?} base_url=${HERMES_BASE_URL:-?} key_env=${HERMES_KEY_ENV:-none}"

# Explicit env wins; else follow Hermes selection
_model="${OPENAI_MODEL:-${OLLAMA_MODEL:-${HERMES_MODEL:-gemma4:31b}}}"
_base="${OPENAI_BASE_URL:-${OLLAMA_BASE_URL:-${HERMES_BASE_URL:-http://127.0.0.1:11434/v1}}}"
_base="$(_ensure_v1 "$_base")"

_backend="${GRAPHIFY_BACKEND:-}"
if [ -z "$_backend" ]; then
  if _is_ollama_url "$_base" || [ "${HERMES_PROVIDER_NAME}" = "local-sage-thor" ]; then
    _backend="ollama"
  else
    _backend="openai"
  fi
fi

TOKEN_BUDGET="${GRAPHIFY_TOKEN_BUDGET:-25000}"
MAX_CONCURRENCY="${GRAPHIFY_MAX_CONCURRENCY:-1}"
API_TIMEOUT="${GRAPHIFY_API_TIMEOUT:-1800}"

echo "==> Graphify backend=$_backend model=$_model base_url=$_base"
echo "==> --token-budget=$TOKEN_BUDGET --max-concurrency=$MAX_CONCURRENCY --api-timeout=$API_TIMEOUT"

if [ "$_backend" = "ollama" ]; then
  export OLLAMA_BASE_URL="$_base"
  export OLLAMA_MODEL="$_model"
  export OLLAMA_API_KEY="${OLLAMA_API_KEY:-ollama}"
  export GRAPHIFY_OLLAMA_KEEP_ALIVE="${GRAPHIFY_OLLAMA_KEEP_ALIVE:-0}"

  if [ -n "${GRAPHIFY_OLLAMA_NUM_CTX:-}" ]; then
    export GRAPHIFY_OLLAMA_NUM_CTX
    echo "==> GRAPHIFY_OLLAMA_NUM_CTX=$GRAPHIFY_OLLAMA_NUM_CTX (manual override)"
  else
    echo "==> GRAPHIFY_OLLAMA_NUM_CTX=auto (graphify derives from chunk size)"
  fi

  _native="${OLLAMA_BASE_URL%/v1}"
  echo "==> Probing Ollama..."
  if ! curl -sf "${_native}/api/tags" >/dev/null; then
    echo "ERROR: cannot reach ${_native}/api/tags — is ollama serve running?" >&2
    exit 1
  fi
  if ! curl -sf "${OLLAMA_BASE_URL}/models" -H "Authorization: Bearer ${OLLAMA_API_KEY}" >/dev/null; then
    echo "ERROR: ${OLLAMA_BASE_URL}/models failed." >&2
    exit 1
  fi
  if ! curl -sf "${_native}/api/tags" | grep -F "\"${OLLAMA_MODEL}\"" >/dev/null 2>&1 \
     && ! curl -sf "${_native}/api/tags" | grep -F "${OLLAMA_MODEL%%:*}" >/dev/null 2>&1; then
    echo "WARNING: model '${OLLAMA_MODEL}' not clearly listed in /api/tags." >&2
  fi

  echo "==> Probing ${OLLAMA_BASE_URL}/chat/completions ..."
  _probe_code=$(curl -s -o /tmp/graphify_ollama_probe.json -w "%{http_code}" \
    -X POST "${OLLAMA_BASE_URL}/chat/completions" \
    -H "Authorization: Bearer ${OLLAMA_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${OLLAMA_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":8}")
  if [ "$_probe_code" != "200" ]; then
    echo "ERROR: chat/completions returned HTTP ${_probe_code}:" >&2
    cat /tmp/graphify_ollama_probe.json >&2 || true
    exit 1
  fi
  echo "==> Probe OK (HTTP 200)"

  echo "==> Extracting knowledge graph (skills/ + docs/) — this is the long step..."
  echo "    ~170+ semantic chunks at concurrency=$MAX_CONCURRENCY; expect hours if many timeouts previously."
  set +e
  "$GRAPHIFY" extract . --backend ollama \
    --token-budget "$TOKEN_BUDGET" \
    --max-concurrency "$MAX_CONCURRENCY" \
    --api-timeout "$API_TIMEOUT"
  _rc=$?
  set -e
else
  # OpenAI-compatible: NRP, NVIDIA Build, OpenRouter, etc.
  export OPENAI_BASE_URL="$_base"
  export OPENAI_MODEL="$_model"

  _api_key="${OPENAI_API_KEY:-}"
  if [ -z "$_api_key" ] && [ -n "${HERMES_KEY_ENV:-}" ]; then
    _api_key="${!HERMES_KEY_ENV:-}"
  fi
  if [ -z "$_api_key" ] && [ -n "${NRP_LLM_API_KEY:-}" ]; then
    _api_key="$NRP_LLM_API_KEY"
  fi
  if [ -z "$_api_key" ] && [ -n "${NVIDIA_API_KEY:-}" ]; then
    _api_key="$NVIDIA_API_KEY"
  fi
  if [ -z "$_api_key" ]; then
    echo "ERROR: OpenAI-compatible backend needs an API key." >&2
    echo "  Set OPENAI_API_KEY, or put ${HERMES_KEY_ENV:-NRP_LLM_API_KEY|NVIDIA_API_KEY} in $ROOT/.env" >&2
    echo "  (Hermes uses the same keys — run hermes model / fill profile .env first.)" >&2
    exit 1
  fi
  export OPENAI_API_KEY="$_api_key"

  echo "==> Probing ${OPENAI_BASE_URL}/models ..."
  if ! curl -sf "${OPENAI_BASE_URL}/models" -H "Authorization: Bearer ${OPENAI_API_KEY}" >/dev/null; then
    echo "ERROR: ${OPENAI_BASE_URL}/models failed (check base_url + API key)." >&2
    exit 1
  fi

  echo "==> Probing ${OPENAI_BASE_URL}/chat/completions ..."
  _probe_code=$(curl -s -o /tmp/graphify_openai_probe.json -w "%{http_code}" \
    -X POST "${OPENAI_BASE_URL}/chat/completions" \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${OPENAI_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":8}")
  if [ "$_probe_code" != "200" ]; then
    echo "ERROR: chat/completions returned HTTP ${_probe_code}:" >&2
    cat /tmp/graphify_openai_probe.json >&2 || true
    exit 1
  fi
  echo "==> Probe OK (HTTP 200)"

  echo "==> Extracting knowledge graph (skills/ + docs/) via OpenAI-compat (${OPENAI_MODEL})..."
  set +e
  "$GRAPHIFY" extract . --backend openai \
    --model "$OPENAI_MODEL" \
    --token-budget "$TOKEN_BUDGET" \
    --max-concurrency "$MAX_CONCURRENCY" \
    --api-timeout "$API_TIMEOUT"
  _rc=$?
  set -e
fi

rm -f "$PIDFILE"

if [ "$_rc" -ne 0 ]; then
  echo "==> [$(date -Is)] FAILED (exit $_rc). See log / output above." >&2
  exit "$_rc"
fi

echo "==> [$(date -Is)] Done. Outputs under $ROOT/graphify-out/"
echo "    Use: $GRAPHIFY query \"...\" --graph graphify-out/graph.json"
echo "    Or:  source $VENV/bin/activate"
exit 0
