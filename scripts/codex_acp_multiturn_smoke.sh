#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v npx >/dev/null 2>&1; then
  echo "npx not found; please install Node.js/npm first." >&2
  exit 2
fi

OUT="/tmp/codex_acp_multiturn_smoke.jsonl"
ERR="/tmp/codex_acp_multiturn_smoke.err"

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

"$BIN" acp client connect \
  --transport stdio \
  --cmd npx \
  --args=-y \
  --args=@zed-industries/codex-acp \
  --cwd "$ROOT_DIR" \
  --prompt "multi-turn smoke one" \
  --prompt "multi-turn smoke two" \
  --request-timeout-ms 30000 \
  --json >"$OUT" 2>"$ERR"

count="$(rg -c '"type":"prompt_result"' "$OUT" || true)"
if [ "$count" -ne 2 ]; then
  echo "expected 2 prompt_result lines, got $count" >&2
  exit 1
fi

sid1="$(rg '"type":"prompt_result"' "$OUT" | sed -n '1p' | sed -E 's/.*"sessionId":"([^"]+)".*/\1/')"
sid2="$(rg '"type":"prompt_result"' "$OUT" | sed -n '2p' | sed -E 's/.*"sessionId":"([^"]+)".*/\1/')"
if [ -z "$sid1" ] || [ "$sid1" != "$sid2" ]; then
  echo "sessionId mismatch: sid1=$sid1 sid2=$sid2" >&2
  exit 1
fi

echo "PASS sessionId=$sid1 prompt_result_count=$count"
