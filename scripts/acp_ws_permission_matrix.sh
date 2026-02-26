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

PORT="${1:-18920}"
SERVER_LOG="/tmp/acp_ws_permission_matrix_server.log"
ALLOW_OUT="/tmp/acp_ws_permission_matrix_allow.jsonl"
DENY_OUT="/tmp/acp_ws_permission_matrix_deny.jsonl"

"$BIN" acp serve \
  --transport ws \
  --listen "127.0.0.1:${PORT}" \
  --permission-mode required \
  --log-level debug >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true' EXIT
sleep 1

"$BIN" acp client connect-ws \
  --endpoint "ws://127.0.0.1:${PORT}" \
  --prompt "permission-matrix" \
  --permission-decision allow \
  --json >"$ALLOW_OUT"

"$BIN" acp client connect-ws \
  --endpoint "ws://127.0.0.1:${PORT}" \
  --prompt "permission-matrix" \
  --permission-decision deny \
  --json >"$DENY_OUT"

allow_reason="$(rg '"type":"prompt_result"' "$ALLOW_OUT" | tail -n1 | sed -E 's/.*"stopReason":"([^"]+)".*/\1/')"
deny_reason="$(rg '"type":"prompt_result"' "$DENY_OUT" | tail -n1 | sed -E 's/.*"stopReason":"([^"]+)".*/\1/')"

if [ "$allow_reason" != "end_turn" ]; then
  echo "allow expected end_turn, got $allow_reason" >&2
  exit 1
fi
if [ "$deny_reason" != "cancelled" ]; then
  echo "deny expected cancelled, got $deny_reason" >&2
  exit 1
fi

echo "PASS allow=$allow_reason deny=$deny_reason port=$PORT"
