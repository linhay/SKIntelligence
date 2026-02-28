#!/usr/bin/env bash
set -euo pipefail

WITH_CODEX=0
STRICT_CODEX=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-codex)
      WITH_CODEX=1
      shift
      ;;
    --strict-codex)
      STRICT_CODEX=1
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      echo "usage: $0 [--with-codex] [--strict-codex]" >&2
      exit 2
      ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

SUMMARY_PATH=".local/acp-summary-latest.json"
mkdir -p .local

export ACP_SUITE_SUMMARY_JSON="$SUMMARY_PATH"
if [[ "$WITH_CODEX" -eq 1 ]]; then
  export RUN_CODEX_PROBES=1
else
  export RUN_CODEX_PROBES=0
fi

if [[ "$STRICT_CODEX" -eq 1 ]]; then
  export STRICT_CODEX_PROBES=1
else
  export STRICT_CODEX_PROBES=0
fi

./scripts/acp_regression_suite.sh

if command -v jq >/dev/null 2>&1; then
  jq '{schemaVersion, ciRecommendation, requiredPassed, stageCounts, alerts}' "$SUMMARY_PATH"
else
  echo "summary: $SUMMARY_PATH"
fi
