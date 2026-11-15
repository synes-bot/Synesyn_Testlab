#!/usr/bin/env bash
# Headless SynAxes discover acceptance (REQ-NDP-024).
# Non-zero exit on test failure. Godot quit(1) and missing PASS line both fail.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLIENT="$ROOT/synesyn_client"
SCRIPT="res://addons/synaxes/tests/test_headless_discover.gd"

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
echo "Running: $SCRIPT (cwd=$CLIENT)"

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

set +e
"$GODOT_BIN" --headless --path "$CLIENT" --script "$SCRIPT" >"$LOG" 2>&1
EXIT_CODE=$?
set -e

cat "$LOG"

if [[ "$EXIT_CODE" -ne 0 ]]; then
  echo "FAIL: SynAxes headless discover exited $EXIT_CODE" >&2
  exit "$EXIT_CODE"
fi

if ! grep -q "SynAxes headless discover: all passed" "$LOG"; then
  echo "FAIL: expected PASS line missing from Godot output" >&2
  exit 1
fi

echo "SynAxes headless discover PASSED"
exit 0
