#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v npx >/dev/null 2>&1; then
  echo "npx not found; please install Node.js/npm first." >&2
  exit 2
fi

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

PROMPT="${1:-执行 shell: date +%s，只返回数字}"
TIMEOUT_MS="${2:-30000}"

run_case() {
  local decision="$1"
  local out="/tmp/codex_acp_permission_probe_${decision}.jsonl"
  local err="/tmp/codex_acp_permission_probe_${decision}.err"

  "$BIN" acp client connect \
    --transport stdio \
    --cmd npx \
    --args=-y \
    --args=@zed-industries/codex-acp \
    --cwd "$ROOT_DIR" \
    --prompt "$PROMPT" \
    --permission-decision "$decision" \
    --request-timeout-ms "$TIMEOUT_MS" \
    --json >"$out" 2>"$err"

  local count
  count="$(sed -n 's/.*permission requests=\([0-9][0-9]*\).*/\1/p' "$err" | tail -n1)"
  local reason
  reason="$(rg '"type":"prompt_result"' "$out" | tail -n1 | sed -E 's/.*"stopReason":"([^"]+)".*/\1/')"
  if [ -z "$count" ] || [ -z "$reason" ]; then
    echo "probe-$decision parse failed" >&2
    exit 1
  fi
  echo "probe-$decision permission_requests=$count stop_reason=$reason"
}

run_case allow
run_case deny
