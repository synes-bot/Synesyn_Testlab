#!/usr/bin/env bash
# Run SynTree embedding-model selection Godot unit tests (headless).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-godot}"
if [[ ! -x "$(command -v "$GODOT_BIN" 2>/dev/null || true)" ]]; then
  if [[ -n "${GODOT_BIN:-}" && -x "$GODOT_BIN" ]]; then
    :
  else
    echo "Godot binary not found. Set GODOT_BIN." >&2
    exit 1
  fi
fi

echo "== SynTree embedding model selection tests =="
"$GODOT_BIN" --headless --path synesyn_client \
  --script res://addons/syntree/tests/test_embedding_model_selection.gd
echo "== SynTree Ollama integration tests (regression) =="
"$GODOT_BIN" --headless --path synesyn_client \
  --script res://addons/syntree/tests/test_ollama_integration.gd
echo "SynTree embedding + Ollama tests OK"
