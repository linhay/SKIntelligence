#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BIN=""
for c in \
  ".build/arm64-apple-macosx/debug/ski" \
  ".build/x86_64-apple-macosx/debug/ski" \
  ".build/debug/ski"; do
  if [ -x "$c" ]; then
    BIN="$c"
    break
  fi
done
if [ -z "$BIN" ]; then
  swift build --product ski >/dev/null
  for c in \
    ".build/arm64-apple-macosx/debug/ski" \
    ".build/x86_64-apple-macosx/debug/ski" \
    ".build/debug/ski"; do
    if [ -x "$c" ]; then
      BIN="$c"
      break
    fi
  done
fi
if [ -z "$BIN" ]; then
  echo "ski binary not found after build" >&2
  exit 1
fi

FIRST_OUT="/tmp/acp_stdio_session_reuse_first.jsonl"
SECOND_OUT="/tmp/acp_stdio_session_reuse_second.jsonl"
SECOND_ERR="/tmp/acp_stdio_session_reuse_second.err"

"$BIN" acp client connect-stdio \
  --cmd "$BIN" \
  --args acp --args serve --args=--transport --args=stdio \
  --prompt "first-turn" \
  --json >"$FIRST_OUT"

SESSION_ID="$(rg '"type":"prompt_result"' "$FIRST_OUT" | tail -n1 | sed -E 's/.*"sessionId":"([^"]+)".*/\1/')"
if [ -z "$SESSION_ID" ]; then
  echo "failed to parse session id from first run" >&2
  exit 1
fi

set +e
"$BIN" acp client connect-stdio \
  --cmd "$BIN" \
  --args acp --args serve --args=--transport --args=stdio \
  --session-id "$SESSION_ID" \
  --prompt "second-turn" \
  --json >"$SECOND_OUT" 2>"$SECOND_ERR"
CODE=$?
set -e

if [ "$CODE" -eq 0 ]; then
  echo "expected failure when reusing stdio session-id across connections, got success" >&2
  exit 1
fi
if [ "$CODE" -ne 4 ]; then
  echo "expected exit code 4, got $CODE" >&2
  exit 1
fi
if ! rg -q "Resource not found|Error:" "$SECOND_ERR"; then
  echo "expected error details in stderr, got:" >&2
  cat "$SECOND_ERR" >&2
  exit 1
fi

echo "PASS expected_failure_exit=$CODE session_id=$SESSION_ID"
