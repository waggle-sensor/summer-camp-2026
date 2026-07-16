#!/usr/bin/env bash
# Required camp setup: venv + pip install Graphify + build skills/docs graph via Ollama.
#
# DEFAULT: runs the long extract in the BACKGROUND (nohup) and returns immediately.
#   ./scripts/setup-graphify.sh              # start background job
#   ./scripts/setup-graphify.sh --status     # pid / log / graph ready?
#   ./scripts/setup-graphify.sh --stop       # kill background job
#   ./scripts/setup-graphify.sh --foreground # block until done (manual / CI)
#
# Why background by default: semantic extract over ~1.8K markdown files takes
# many minutes on Thor+Ollama and will timeout Hermes/agent foreground tools.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
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

Env: OLLAMA_BASE_URL (must end in /v1), OLLAMA_MODEL, GRAPHIFY_TOKEN_BUDGET (default 25000),
     GRAPHIFY_FOREGROUND=1 (same as --foreground), GRAPHIFY_VENV, GRAPHIFY_OLLAMA_NUM_CTX
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

  # Preserve useful env into the child
  nohup env \
    OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-}" \
    OLLAMA_MODEL="${OLLAMA_MODEL:-}" \
    OLLAMA_API_KEY="${OLLAMA_API_KEY:-}" \
    GRAPHIFY_TOKEN_BUDGET="${GRAPHIFY_TOKEN_BUDGET:-}" \
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

# graphify --backend ollama uses the OpenAI Python client → URL must end in /v1
_raw_url="${OLLAMA_BASE_URL:-http://127.0.0.1:11434/v1}"
_raw_url="${_raw_url%/}"
case "$_raw_url" in
  */v1) ;;
  *)
    echo "==> NOTE: appending /v1 to OLLAMA_BASE_URL for OpenAI-compat (was: $_raw_url)"
    _raw_url="${_raw_url}/v1"
    ;;
esac
export OLLAMA_BASE_URL="$_raw_url"
export OLLAMA_MODEL="${OLLAMA_MODEL:-gemma4:31b}"
export OLLAMA_API_KEY="${OLLAMA_API_KEY:-ollama}"
export GRAPHIFY_OLLAMA_KEEP_ALIVE="${GRAPHIFY_OLLAMA_KEEP_ALIVE:-0}"

if [ -n "${GRAPHIFY_OLLAMA_NUM_CTX:-}" ]; then
  export GRAPHIFY_OLLAMA_NUM_CTX
  echo "==> GRAPHIFY_OLLAMA_NUM_CTX=$GRAPHIFY_OLLAMA_NUM_CTX (manual override)"
else
  echo "==> GRAPHIFY_OLLAMA_NUM_CTX=auto (graphify derives from chunk size)"
fi
TOKEN_BUDGET="${GRAPHIFY_TOKEN_BUDGET:-25000}"

echo "==> OLLAMA_BASE_URL=$OLLAMA_BASE_URL"
echo "==> OLLAMA_MODEL=$OLLAMA_MODEL"
echo "==> --token-budget=$TOKEN_BUDGET"

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
set +e
"$GRAPHIFY" extract . --backend ollama --token-budget "$TOKEN_BUDGET"
_rc=$?
set -e

rm -f "$PIDFILE"

if [ "$_rc" -ne 0 ]; then
  echo "==> [$(date -Is)] FAILED (exit $_rc). See log / output above." >&2
  exit "$_rc"
fi

echo "==> [$(date -Is)] Done. Outputs under $ROOT/graphify-out/"
echo "    Use: $GRAPHIFY query \"...\" --graph graphify-out/graph.json"
echo "    Or:  source $VENV/bin/activate"
exit 0
