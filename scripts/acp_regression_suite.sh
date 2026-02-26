#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
PORT_BASE="${ACP_PORT_BASE:-18920}"
CODEX_PROBE_RETRIES="${CODEX_PROBE_RETRIES:-2}"
CODEX_PROBE_RETRY_DELAY_SECONDS="${CODEX_PROBE_RETRY_DELAY_SECONDS:-2}"
STRICT_CODEX_PROBES="${STRICT_CODEX_PROBES:-0}"
SUMMARY_JSON_PATH="${ACP_SUITE_SUMMARY_JSON:-}"
SUMMARY_LINES=""
SUITE_RESULT="fail"

if ! [[ "$CODEX_PROBE_RETRIES" =~ ^[0-9]+$ ]] || [ "$CODEX_PROBE_RETRIES" -lt 1 ]; then
  echo "CODEX_PROBE_RETRIES must be a positive integer" >&2
  exit 2
fi
if ! [[ "$CODEX_PROBE_RETRY_DELAY_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "CODEX_PROBE_RETRY_DELAY_SECONDS must be a non-negative integer" >&2
  exit 2
fi
if [ "$STRICT_CODEX_PROBES" != "0" ] && [ "$STRICT_CODEX_PROBES" != "1" ]; then
  echo "STRICT_CODEX_PROBES must be 0 or 1" >&2
  exit 2
fi

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

append_summary() {
  local stage="$1"
  local status="$2"
  local required="$3"
  local exit_code="$4"
  local message="$5"
  SUMMARY_LINES+="${stage}|${status}|${required}|${exit_code}|${message}"$'\n'
}

write_summary_json() {
  if [ -z "$SUMMARY_JSON_PATH" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$SUMMARY_JSON_PATH")"
  {
    printf '{\n'
    printf '  "result": "%s",\n' "$(json_escape "$SUITE_RESULT")"
    printf '  "strictCodexProbes": %s,\n' "$STRICT_CODEX_PROBES"
    printf '  "runCodexProbes": %s,\n' "${RUN_CODEX_PROBES:-0}"
    printf '  "stages": [\n'
    local first=1
    while IFS='|' read -r stage status required exit_code message; do
      [ -z "$stage" ] && continue
      if [ "$first" -eq 0 ]; then
        printf ',\n'
      fi
      first=0
      printf '    {"stage":"%s","status":"%s","required":%s,"exitCode":%s,"message":"%s"}' \
        "$(json_escape "$stage")" \
        "$(json_escape "$status")" \
        "$required" \
        "$exit_code" \
        "$(json_escape "$message")"
    done <<< "$SUMMARY_LINES"
    printf '\n  ]\n'
    printf '}\n'
  } > "$SUMMARY_JSON_PATH"
}

trap write_summary_json EXIT

run_with_retry() {
  local cmd="$1"
  local label="$2"
  local max_attempts="${3:-2}"
  local delay_seconds="${4:-0}"
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
      if [ "$delay_seconds" -gt 0 ]; then
        sleep "$delay_seconds"
      fi
    fi
    attempt=$((attempt + 1))
  done

  echo "[suite] FAIL ${label} exit=${exit_code}"
  return "$exit_code"
}

run_required_stage() {
  local stage="$1"
  local label="$2"
  local cmd="$3"
  echo "$label"
  set +e
  eval "$cmd"
  local exit_code=$?
  set -e
  if [ "$exit_code" -eq 0 ]; then
    append_summary "$stage" "pass" "true" "$exit_code" "ok"
    return 0
  fi
  append_summary "$stage" "fail" "true" "$exit_code" "required stage failed"
  return "$exit_code"
}

run_optional_stage() {
  local stage="$1"
  local label="$2"
  local cmd="$3"
  echo "$label"
  if run_with_retry "$cmd" "$stage" "$CODEX_PROBE_RETRIES" "$CODEX_PROBE_RETRY_DELAY_SECONDS"; then
    append_summary "$stage" "pass" "false" "0" "ok"
    return 0
  fi
  if [ "$STRICT_CODEX_PROBES" = "1" ]; then
    append_summary "$stage" "fail" "false" "1" "failed under strict mode"
    echo "[suite] FAIL ${stage} failed under strict mode"
    return 1
  fi
  append_summary "$stage" "warn" "false" "1" "failed but allowed in non-strict mode"
  echo "[suite] WARN ${stage} exhausted retries (continuing)"
  return 0
}

run_required_stage "ws_permission_matrix" "[suite] 1/5 ws permission matrix" "./scripts/acp_ws_permission_matrix.sh \"$((PORT_BASE + 0))\""
run_required_stage "ws_session_reuse" "[suite] 2/5 ws session reuse" "./scripts/acp_ws_session_reuse_probe.sh \"$((PORT_BASE + 10))\""
run_required_stage "stdio_session_reuse_boundary" "[suite] 3/5 stdio session reuse boundary" "./scripts/acp_stdio_session_reuse_probe.sh"
run_required_stage "ws_ttl_zero_boundary" "[suite] 4/5 ws ttl-zero immediate-expiry boundary" "./scripts/acp_ws_ttl_zero_probe.sh \"$((PORT_BASE + 11))\""
run_required_stage "ws_timeout_zero_boundary" "[suite] 5/5 ws timeout-zero no-timeout boundary" "./scripts/acp_ws_timeout_zero_probe.sh \"$((PORT_BASE + 12))\""

if [ "${RUN_CODEX_PROBES:-0}" = "1" ]; then
  run_optional_stage "codex_permission_probe" "[suite] 6/7 codex permission probe (optional)" "./scripts/codex_acp_permission_probe.sh"
  run_optional_stage "codex_multiturn_smoke" "[suite] 7/7 codex multi-turn smoke (optional)" "./scripts/codex_acp_multiturn_smoke.sh"
fi

SUITE_RESULT="pass"
echo "[suite] PASS"
