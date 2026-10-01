#!/usr/bin/env bash
set -e

# Determine repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

echo "=== Verifying Checkpoint 6 (Confirmed Actions) ==="

# 1. Python compilation check for chat router
python3 -m compileall -q backend/routers/chat.py

# 2. Targeted backend test execution
if [ -x "$REPO_ROOT/.venv/bin/python3" ]; then
  PYTHON_BIN="$REPO_ROOT/.venv/bin/python3"
else
  PYTHON_BIN="python3"
fi

"$PYTHON_BIN" -m unittest -v backend/tests/test_chat_actions_final.py

# 3. Targeted Flutter chat action confirmation tests
if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter command not found. Flutter verification is required for Checkpoint 6." >&2
  exit 1
fi

echo "Running targeted Flutter chat action tests..."
(cd "$REPO_ROOT/frontend" && flutter test --plain-name "Checkpoint 4a" test/chat_history_test.dart)

echo "=== Checkpoint 6: PASS ==="
