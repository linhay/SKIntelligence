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

PORT="${1:-18932}"
SERVER_LOG="/tmp/acp_ws_timeout_zero_server.log"
CLIENT_OUT="/tmp/acp_ws_timeout_zero_client.out"

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
  --request-timeout-ms=0 \
  --prompt "ws timeout zero check" \
  --json >"$CLIENT_OUT"

STOP_REASON="$(rg '"type":"prompt_result"' "$CLIENT_OUT" | tail -n1 | sed -E 's/.*"stopReason":"([^"]+)".*/\1/')"
if [ "$STOP_REASON" != "end_turn" ]; then
  echo "expected stopReason=end_turn, got $STOP_REASON" >&2
  exit 1
fi

echo "PASS stop_reason=$STOP_REASON port=$PORT"
