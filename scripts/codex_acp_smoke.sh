#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v npx >/dev/null 2>&1; then
  echo "npx not found; please install Node.js/npm first." >&2
  exit 2
fi

RUNS="${1:-3}"
ok=0

for i in $(seq 1 "$RUNS"); do
  out="/tmp/codex_acp_smoke_${i}.jsonl"
  err="/tmp/codex_acp_smoke_${i}.err"
  if swift run ski acp client connect \
    --transport stdio \
    --cmd npx \
    --args=-y \
    --args=@zed-industries/codex-acp \
    --cwd "$ROOT_DIR" \
    --prompt "smoke-$i: reply OK" \
    --json >"$out" 2>"$err"; then
    if rg -q '"type":"prompt_result"' "$out"; then
      ok=$((ok + 1))
      echo "run $i: PASS"
    else
      echo "run $i: NO_PROMPT_RESULT"
    fi
  else
    echo "run $i: FAIL"
  fi
done

echo "success=$ok/$RUNS"
if [ "$ok" -ne "$RUNS" ]; then
  exit 1
fi

