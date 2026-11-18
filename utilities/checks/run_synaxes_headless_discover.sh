#!/usr/bin/env bash
# Headless SynAxes discover acceptance (REQ-NDP-024).
# Non-zero exit on test failure. Godot quit(1) and missing PASS line both fail.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLIENT="$ROOT/synesyn_client"
SCRIPT="res://addons/synaxes/tests/test_headless_discover.gd"
PERSIST_SCRIPT="res://addons/synaxes/tests/test_persist_demo_analysis.gd"
LABELS_SCRIPT="res://addons/synaxes/tests/test_theme_labels.gd"

GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot)"
  elif [[ -x "$HOME/bin/godot" ]]; then
    GODOT_BIN="$HOME/bin/godot"
  else
    echo "Godot executable not found. Set GODOT_BIN or install godot on PATH." >&2
    exit 127
  fi
fi

echo "Using Godot: $GODOT_BIN"

run_godot_script() {
  local script_path="$1"
  local pass_line="$2"
  local label="$3"
  echo "Running: $script_path (cwd=$CLIENT)"
  local log
  log="$(mktemp)"
  set +e
  "$GODOT_BIN" --headless --path "$CLIENT" --script "$script_path" >"$log" 2>&1
  local exit_code=$?
  set -e
  cat "$log"
  if [[ "$exit_code" -ne 0 ]]; then
    echo "FAIL: $label exited $exit_code" >&2
    rm -f "$log"
    exit "$exit_code"
  fi
  if ! grep -q "$pass_line" "$log"; then
    echo "FAIL: expected PASS line missing from Godot output ($label)" >&2
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"
  echo "$label PASSED"
}

run_godot_script "$SCRIPT" "SynAxes headless discover: all passed" "SynAxes headless discover"
run_godot_script "$PERSIST_SCRIPT" "SynAxes persist demo analysis: all passed" "SynAxes persist demo analysis"
run_godot_script "$LABELS_SCRIPT" "SynAxes theme labels: all passed" "SynAxes theme labels"
exit 0
