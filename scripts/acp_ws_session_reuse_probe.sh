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

PORT="${1:-18930}"
SERVER_LOG="/tmp/acp_ws_session_reuse_server.log"
FIRST_OUT="/tmp/acp_ws_session_reuse_first.jsonl"
SECOND_OUT="/tmp/acp_ws_session_reuse_second.jsonl"

"$BIN" acp serve \
  --transport ws \
  --listen "127.0.0.1:${PORT}" \
  --permission-mode permissive \
  --log-level debug >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true' EXIT
sleep 1

"$BIN" acp client connect-ws \
  --endpoint "ws://127.0.0.1:${PORT}" \
  --prompt "first-turn" \
  --json >"$FIRST_OUT"

SESSION_ID="$(rg '"type":"prompt_result"' "$FIRST_OUT" | tail -n1 | sed -E 's/.*"sessionId":"([^"]+)".*/\1/')"
if [ -z "$SESSION_ID" ]; then
  echo "failed to parse session id from first run" >&2
  exit 1
fi

"$BIN" acp client connect-ws \
  --endpoint "ws://127.0.0.1:${PORT}" \
  --session-id "$SESSION_ID" \
  --prompt "second-turn" \
  --json >"$SECOND_OUT"

SECOND_SESSION_ID="$(rg '"type":"prompt_result"' "$SECOND_OUT" | tail -n1 | sed -E 's/.*"sessionId":"([^"]+)".*/\1/')"
SECOND_REASON="$(rg '"type":"prompt_result"' "$SECOND_OUT" | tail -n1 | sed -E 's/.*"stopReason":"([^"]+)".*/\1/')"

if [ "$SECOND_SESSION_ID" != "$SESSION_ID" ]; then
  echo "session mismatch first=$SESSION_ID second=$SECOND_SESSION_ID" >&2
  exit 1
fi
if [ "$SECOND_REASON" != "end_turn" ]; then
  echo "unexpected stop reason: $SECOND_REASON" >&2
  exit 1
fi

echo "PASS session_id=$SESSION_ID stop_reason=$SECOND_REASON"
