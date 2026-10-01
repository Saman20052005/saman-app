#!/usr/bin/env bash
set -e

# Determine repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

echo "=== Verifying Checkpoint 3 (7-Day Trends) ==="

# 1. Python compilation check for chat router
python3 -m compileall -q backend/routers/chat.py

# 2. Targeted test execution
if [ -x "$REPO_ROOT/.venv/bin/python3" ]; then
  PYTHON_BIN="$REPO_ROOT/.venv/bin/python3"
else
  PYTHON_BIN="python3"
fi

"$PYTHON_BIN" -m unittest -v backend/tests/test_chat_trends.py

echo "=== Checkpoint 3: PASS ==="
