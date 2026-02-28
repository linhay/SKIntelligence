#!/usr/bin/env bash
set -euo pipefail

PROMPT="${1:-hello}"

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

swift run ski acp client connect \
  --transport stdio \
  --cmd npx \
  --args=-y \
  --args=@zed-industries/codex-acp \
  --cwd "$ROOT" \
  --prompt "$PROMPT" \
  --json
