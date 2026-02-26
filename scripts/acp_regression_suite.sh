#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[suite] 1/3 ws permission matrix"
./scripts/acp_ws_permission_matrix.sh

echo "[suite] 2/3 ws session reuse"
./scripts/acp_ws_session_reuse_probe.sh

echo "[suite] 3/3 stdio session reuse boundary"
./scripts/acp_stdio_session_reuse_probe.sh

if [ "${RUN_CODEX_PROBES:-0}" = "1" ]; then
  echo "[suite] codex permission probe (optional)"
  ./scripts/codex_acp_permission_probe.sh
fi

echo "[suite] PASS"
