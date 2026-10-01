#!/usr/bin/env bash
set -e

# Determine repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

echo "=== Verifying Checkpoint 1 (Reliable Chat Baseline) ==="

# 1. Python compilation check for chat router
python3 -m compileall -q backend/routers/chat.py

# 2. Targeted test execution
# Prefer repo virtualenv if available, fallback to python3
if [ -x "$REPO_ROOT/.venv/bin/python3" ]; then
  PYTHON_BIN="$REPO_ROOT/.venv/bin/python3"
else
  PYTHON_BIN="python3"
fi

CP1_TESTS=(
  backend.tests.test_chat.TestChatCheckpoint1And2.test_success_json
  backend.tests.test_chat.TestChatCheckpoint1And2.test_missing_token_401
  backend.tests.test_chat.TestChatCheckpoint1And2.test_invalid_token_401
  backend.tests.test_chat.TestChatCheckpoint1And2.test_user_not_found_401
  backend.tests.test_chat.TestChatCheckpoint1And2.test_empty_message_rejected
  backend.tests.test_chat.TestChatCheckpoint1And2.test_timeout_504
  backend.tests.test_chat.TestChatCheckpoint1And2.test_provider_error_503
  backend.tests.test_chat.TestChatCheckpoint1And2.test_empty_reply_503
  backend.tests.test_chat.TestChatCheckpoint1And2.test_gemini_fails_openai_fallback_success
  backend.tests.test_chat.TestChatCheckpoint1And2.test_missing_config_503
  backend.tests.test_chat.TestChatCheckpoint1And2.test_flutter_payload_compatibility
)

"$PYTHON_BIN" -m unittest -v "${CP1_TESTS[@]}"

echo "=== Checkpoint 1: PASS ==="
