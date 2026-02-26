#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
PORT_BASE="${ACP_PORT_BASE:-18920}"
CODEX_PROBE_RETRIES="${CODEX_PROBE_RETRIES:-2}"
CODEX_PROBE_RETRY_DELAY_SECONDS="${CODEX_PROBE_RETRY_DELAY_SECONDS:-2}"
STRICT_CODEX_PROBES="${STRICT_CODEX_PROBES:-0}"
SUMMARY_JSON_PATH="${ACP_SUITE_SUMMARY_JSON:-}"
SUMMARY_SCHEMA_VERSION="1"
SUMMARY_LINES=""
SUITE_RESULT="fail"
SUITE_STARTED_AT_EPOCH="$(date +%s)"
SUITE_STARTED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SUITE_RUN_ID="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12 || true)"
if [ -z "$SUITE_RUN_ID" ]; then
  SUITE_RUN_ID="$(date +%s)"
fi
RETRY_LAST_ATTEMPTS=0
RETRY_LAST_EXIT_CODE=0

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
  local index="$1"
  local stage="$2"
  local status="$3"
  local required="$4"
  local exit_code="$5"
  local duration_seconds="$6"
  local attempts="$7"
  local message="$8"
  SUMMARY_LINES+="${index}|${stage}|${status}|${required}|${exit_code}|${duration_seconds}|${attempts}|${message}"$'\n'
}

write_summary_json() {
  if [ -z "$SUMMARY_JSON_PATH" ]; then
    return 0
  fi
  local finished_at_epoch
  local finished_at_utc
  local duration_seconds
  local summary_dir
  local summary_tmp
  finished_at_epoch="$(date +%s)"
  finished_at_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  duration_seconds="$((finished_at_epoch - SUITE_STARTED_AT_EPOCH))"
  summary_dir="$(dirname "$SUMMARY_JSON_PATH")"
  mkdir -p "$summary_dir"
  summary_tmp="$(mktemp "$summary_dir/.acp-summary.XXXXXX.json")"
  {
    printf '{\n'
    printf '  "schemaVersion": "%s",\n' "$(json_escape "$SUMMARY_SCHEMA_VERSION")"
    printf '  "runId": "%s",\n' "$(json_escape "$SUITE_RUN_ID")"
    printf '  "result": "%s",\n' "$(json_escape "$SUITE_RESULT")"
    printf '  "startedAtUtc": "%s",\n' "$(json_escape "$SUITE_STARTED_AT_UTC")"
    printf '  "finishedAtUtc": "%s",\n' "$(json_escape "$finished_at_utc")"
    printf '  "durationSeconds": %s,\n' "$duration_seconds"
    printf '  "strictCodexProbes": %s,\n' "$STRICT_CODEX_PROBES"
    printf '  "runCodexProbes": %s,\n' "${RUN_CODEX_PROBES:-0}"
    printf '  "config": {\n'
    printf '    "portBase": %s,\n' "$PORT_BASE"
    printf '    "codexProbeRetries": %s,\n' "$CODEX_PROBE_RETRIES"
    printf '    "codexProbeRetryDelaySeconds": %s,\n' "$CODEX_PROBE_RETRY_DELAY_SECONDS"
    printf '    "strictCodexProbes": %s,\n' "$STRICT_CODEX_PROBES"
    printf '    "runCodexProbes": %s\n' "${RUN_CODEX_PROBES:-0}"
    printf '  },\n'
    printf '  "stages": [\n'
    local first=1
    while IFS='|' read -r index stage status required exit_code duration_seconds attempts message; do
      [ -z "$index" ] && continue
      if [ "$first" -eq 0 ]; then
        printf ',\n'
      fi
      first=0
      printf '    {"index":%s,"stage":"%s","status":"%s","required":%s,"exitCode":%s,"durationSeconds":%s,"attempts":%s,"message":"%s"}' \
        "$index" \
        "$(json_escape "$stage")" \
        "$(json_escape "$status")" \
        "$required" \
        "$exit_code" \
        "$duration_seconds" \
        "$attempts" \
        "$(json_escape "$message")"
    done <<< "$SUMMARY_LINES"
    printf '\n  ]\n'
    printf '}\n'
  } > "$summary_tmp"
  mv "$summary_tmp" "$SUMMARY_JSON_PATH"

  # Lightweight guard against accidental format drift.
  if ! rg -q '"schemaVersion":' "$SUMMARY_JSON_PATH" || ! rg -q '"stages": \[' "$SUMMARY_JSON_PATH"; then
    echo "summary json validation failed: missing schemaVersion or stages" >&2
    return 1
  fi
}

trap write_summary_json EXIT

run_with_retry() {
  local cmd="$1"
  local label="$2"
  local max_attempts="${3:-2}"
  local delay_seconds="${4:-0}"
  local attempt=1
  local exit_code=0

  RETRY_LAST_ATTEMPTS=0
  RETRY_LAST_EXIT_CODE=0
  while [ "$attempt" -le "$max_attempts" ]; do
    set +e
    eval "$cmd"
    exit_code=$?
    set -e

    if [ "$exit_code" -eq 0 ]; then
      RETRY_LAST_ATTEMPTS="$attempt"
      RETRY_LAST_EXIT_CODE="$exit_code"
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

  RETRY_LAST_ATTEMPTS="$max_attempts"
  RETRY_LAST_EXIT_CODE="$exit_code"
  echo "[suite] FAIL ${label} exit=${exit_code}"
  return "$exit_code"
}

run_required_stage() {
  local index="$1"
  local stage="$2"
  local label="$3"
  local cmd="$4"
  local started_at_epoch
  local ended_at_epoch
  local duration_seconds
  started_at_epoch="$(date +%s)"
  echo "$label"
  set +e
  eval "$cmd"
  local exit_code=$?
  set -e
  ended_at_epoch="$(date +%s)"
  duration_seconds="$((ended_at_epoch - started_at_epoch))"
  if [ "$exit_code" -eq 0 ]; then
    append_summary "$index" "$stage" "pass" "true" "$exit_code" "$duration_seconds" "1" "ok"
    return 0
  fi
  append_summary "$index" "$stage" "fail" "true" "$exit_code" "$duration_seconds" "1" "required stage failed"
  return "$exit_code"
}

run_optional_stage() {
  local index="$1"
  local stage="$2"
  local label="$3"
  local cmd="$4"
  local started_at_epoch
  local ended_at_epoch
  local duration_seconds
  started_at_epoch="$(date +%s)"
  echo "$label"
  if run_with_retry "$cmd" "$stage" "$CODEX_PROBE_RETRIES" "$CODEX_PROBE_RETRY_DELAY_SECONDS"; then
    ended_at_epoch="$(date +%s)"
    duration_seconds="$((ended_at_epoch - started_at_epoch))"
    append_summary "$index" "$stage" "pass" "false" "0" "$duration_seconds" "$RETRY_LAST_ATTEMPTS" "ok"
    return 0
  fi
  ended_at_epoch="$(date +%s)"
  duration_seconds="$((ended_at_epoch - started_at_epoch))"
  if [ "$STRICT_CODEX_PROBES" = "1" ]; then
    append_summary "$index" "$stage" "fail" "false" "$RETRY_LAST_EXIT_CODE" "$duration_seconds" "$RETRY_LAST_ATTEMPTS" "failed under strict mode"
    echo "[suite] FAIL ${stage} failed under strict mode"
    return 1
  fi
  append_summary "$index" "$stage" "warn" "false" "$RETRY_LAST_EXIT_CODE" "$duration_seconds" "$RETRY_LAST_ATTEMPTS" "failed but allowed in non-strict mode"
  echo "[suite] WARN ${stage} exhausted retries (continuing)"
  return 0
}

run_required_stage "1" "ws_permission_matrix" "[suite] 1/5 ws permission matrix" "./scripts/acp_ws_permission_matrix.sh \"$((PORT_BASE + 0))\""
run_required_stage "2" "ws_session_reuse" "[suite] 2/5 ws session reuse" "./scripts/acp_ws_session_reuse_probe.sh \"$((PORT_BASE + 10))\""
run_required_stage "3" "stdio_session_reuse_boundary" "[suite] 3/5 stdio session reuse boundary" "./scripts/acp_stdio_session_reuse_probe.sh"
run_required_stage "4" "ws_ttl_zero_boundary" "[suite] 4/5 ws ttl-zero immediate-expiry boundary" "./scripts/acp_ws_ttl_zero_probe.sh \"$((PORT_BASE + 11))\""
run_required_stage "5" "ws_timeout_zero_boundary" "[suite] 5/5 ws timeout-zero no-timeout boundary" "./scripts/acp_ws_timeout_zero_probe.sh \"$((PORT_BASE + 12))\""

if [ "${RUN_CODEX_PROBES:-0}" = "1" ]; then
  run_optional_stage "6" "codex_permission_probe" "[suite] 6/7 codex permission probe (optional)" "./scripts/codex_acp_permission_probe.sh"
  run_optional_stage "7" "codex_multiturn_smoke" "[suite] 7/7 codex multi-turn smoke (optional)" "./scripts/codex_acp_multiturn_smoke.sh"
else
  append_summary "6" "codex_permission_probe" "skipped" "false" "0" "0" "0" "skipped (RUN_CODEX_PROBES=0)"
  append_summary "7" "codex_multiturn_smoke" "skipped" "false" "0" "0" "0" "skipped (RUN_CODEX_PROBES=0)"
fi

SUITE_RESULT="pass"
echo "[suite] PASS"
