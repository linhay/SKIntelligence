#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

run_with_retry() {
  local cmd="$1"
  local label="$2"
  local max_attempts=2
  local attempt=1
  local exit_code=0

  while [ "$attempt" -le "$max_attempts" ]; do
    if eval "$cmd"; then
      return 0
    fi
    exit_code=$?
    if [ "$attempt" -lt "$max_attempts" ]; then
      echo "[suite] WARN ${label} failed with exit=${exit_code}, retry ${attempt}/${max_attempts}"
    fi
    attempt=$((attempt + 1))
  done

  echo "[suite] FAIL ${label} exit=${exit_code}"
  return "$exit_code"
}

echo "[suite] 1/3 ws permission matrix"
./scripts/acp_ws_permission_matrix.sh

echo "[suite] 2/3 ws session reuse"
./scripts/acp_ws_session_reuse_probe.sh

echo "[suite] 3/3 stdio session reuse boundary"
./scripts/acp_stdio_session_reuse_probe.sh

if [ "${RUN_CODEX_PROBES:-0}" = "1" ]; then
  echo "[suite] 4/5 codex permission probe (optional)"
  run_with_retry "./scripts/codex_acp_permission_probe.sh" "codex permission probe"

  echo "[suite] 5/5 codex multi-turn smoke (optional)"
  run_with_retry "./scripts/codex_acp_multiturn_smoke.sh" "codex multi-turn smoke"
fi

echo "[suite] PASS"
