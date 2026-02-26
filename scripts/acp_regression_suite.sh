#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
PORT_BASE="${ACP_PORT_BASE:-18920}"
CODEX_PROBE_RETRIES="${CODEX_PROBE_RETRIES:-2}"

if ! [[ "$CODEX_PROBE_RETRIES" =~ ^[0-9]+$ ]] || [ "$CODEX_PROBE_RETRIES" -lt 1 ]; then
  echo "CODEX_PROBE_RETRIES must be a positive integer" >&2
  exit 2
fi

run_with_retry() {
  local cmd="$1"
  local label="$2"
  local max_attempts="${3:-2}"
  local attempt=1
  local exit_code=0

  while [ "$attempt" -le "$max_attempts" ]; do
    set +e
    eval "$cmd"
    exit_code=$?
    set -e

    if [ "$exit_code" -eq 0 ]; then
      return 0
    fi
    if [ "$attempt" -lt "$max_attempts" ]; then
      echo "[suite] WARN ${label} failed with exit=${exit_code}, retry ${attempt}/${max_attempts}"
    fi
    attempt=$((attempt + 1))
  done

  echo "[suite] FAIL ${label} exit=${exit_code}"
  return "$exit_code"
}

echo "[suite] 1/5 ws permission matrix"
./scripts/acp_ws_permission_matrix.sh "$((PORT_BASE + 0))"

echo "[suite] 2/5 ws session reuse"
./scripts/acp_ws_session_reuse_probe.sh "$((PORT_BASE + 10))"

echo "[suite] 3/5 stdio session reuse boundary"
./scripts/acp_stdio_session_reuse_probe.sh

echo "[suite] 4/5 ws ttl-zero immediate-expiry boundary"
./scripts/acp_ws_ttl_zero_probe.sh "$((PORT_BASE + 11))"

echo "[suite] 5/5 ws timeout-zero no-timeout boundary"
./scripts/acp_ws_timeout_zero_probe.sh "$((PORT_BASE + 12))"

if [ "${RUN_CODEX_PROBES:-0}" = "1" ]; then
  echo "[suite] 6/7 codex permission probe (optional)"
  run_with_retry "./scripts/codex_acp_permission_probe.sh" "codex permission probe" "$CODEX_PROBE_RETRIES" || \
    echo "[suite] WARN codex permission probe exhausted retries (continuing)"

  echo "[suite] 7/7 codex multi-turn smoke (optional)"
  run_with_retry "./scripts/codex_acp_multiturn_smoke.sh" "codex multi-turn smoke" "$CODEX_PROBE_RETRIES" || \
    echo "[suite] WARN codex multi-turn smoke exhausted retries (continuing)"
fi

echo "[suite] PASS"
