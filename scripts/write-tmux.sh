#!/bin/sh

# Confirm we're in a tmux session and capture full scrollback WITH ANSI escapes (-e), from start of history (-S -)
if [ -n "$TMUX" ]; then
  TS=$(date +%Y%m%d_%H%M%S)
  OUT=~/AI-projects/tmux-logs/transcript_${TS}.ansi
  mkdir -p ~/AI-projects/tmux-logs
  tmux capture-pane -p -e -S - > "$OUT"
  echo "saved: $OUT"
  wc -l "$OUT"; ls -l "$OUT"
else
  echo "NOT inside a tmux session (\$TMUX is empty)."
  echo "Available tmux sessions:"
  tmux ls 2>/dev/null || echo "  (tmux server not running / no sessions)"
fi
