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

PORT="${1:-18931}"
SERVER_LOG="/tmp/acp_ws_ttl_zero_server.log"
CLIENT_OUT="/tmp/acp_ws_ttl_zero_client.out"
CLIENT_ERR="/tmp/acp_ws_ttl_zero_client.err"

"$BIN" acp serve \
  --transport ws \
  --listen "127.0.0.1:${PORT}" \
  --session-ttl-ms=0 \
  --permission-mode permissive \
  --log-level debug >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true' EXIT
sleep 1

set +e
"$BIN" acp client connect-ws \
  --endpoint "ws://127.0.0.1:${PORT}" \
  --prompt "ws session ttl zero check" >"$CLIENT_OUT" 2>"$CLIENT_ERR"
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -ne 4 ]; then
  echo "expected exit=4 when session ttl is zero, got exit=$EXIT_CODE" >&2
  cat "$CLIENT_ERR" >&2 || true
  exit 1
fi

if ! rg -q "Session not found" "$CLIENT_ERR"; then
  echo "expected stderr to contain 'Session not found'" >&2
  cat "$CLIENT_ERR" >&2 || true
  exit 1
fi

echo "PASS exit=$EXIT_CODE reason=session_not_found port=$PORT"
