#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
PORT_BASE="${ACP_PORT_BASE:-18920}"
CODEX_PROBE_RETRIES="${CODEX_PROBE_RETRIES:-2}"
CODEX_PROBE_RETRY_DELAY_SECONDS="${CODEX_PROBE_RETRY_DELAY_SECONDS:-2}"
STRICT_CODEX_PROBES="${STRICT_CODEX_PROBES:-0}"
SUMMARY_JSON_PATH="${ACP_SUITE_SUMMARY_JSON:-}"
SUMMARY_SCHEMA_VERSION="3"
SUMMARY_LINES=""
SUITE_RESULT="fail"
SUITE_STARTED_AT_EPOCH="$(date +%s)"
SUITE_STARTED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SUITE_RUN_ID="${ACP_SUITE_RUN_ID:-}"
if [ -z "$SUITE_RUN_ID" ]; then
  SUITE_RUN_ID="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12 || true)"
fi
if [ -z "$SUITE_RUN_ID" ]; then
  SUITE_RUN_ID="$(date +%s)"
fi
SUITE_LOG_DIR="${ACP_SUITE_LOG_DIR:-.local/acp-suite-logs/$SUITE_RUN_ID}"
GIT_HEAD="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
GIT_DIRTY="false"
if ! git diff --quiet --ignore-submodules -- 2>/dev/null || ! git diff --cached --quiet --ignore-submodules -- 2>/dev/null; then
  GIT_DIRTY="true"
fi
HOST_NAME="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
HOST_OS="$(uname -s 2>/dev/null || echo unknown)"
HOST_ARCH="$(uname -m 2>/dev/null || echo unknown)"
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
  local started_at_utc="$6"
  local finished_at_utc="$7"
  local duration_seconds="$8"
  local attempts="$9"
  local message="${10}"
  local log_path="${11:-}"
  SUMMARY_LINES+="${index}|${stage}|${status}|${required}|${exit_code}|${started_at_utc}|${finished_at_utc}|${duration_seconds}|${attempts}|${message}|${log_path}"$'\n'
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
  local count_total=0
  local count_pass=0
  local count_fail=0
  local count_warn=0
  local count_skipped=0
  finished_at_epoch="$(date +%s)"
  finished_at_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  duration_seconds="$((finished_at_epoch - SUITE_STARTED_AT_EPOCH))"
  while IFS='|' read -r _index _stage _status _required _exit_code _started_at_utc _finished_at_utc _duration_seconds _attempts _message _log_path; do
    [ -z "$_index" ] && continue
    count_total=$((count_total + 1))
    case "$_status" in
      pass) count_pass=$((count_pass + 1)) ;;
      fail) count_fail=$((count_fail + 1)) ;;
      warn) count_warn=$((count_warn + 1)) ;;
      skipped) count_skipped=$((count_skipped + 1)) ;;
    esac
  done <<< "$SUMMARY_LINES"
  summary_dir="$(dirname "$SUMMARY_JSON_PATH")"
  mkdir -p "$SUITE_LOG_DIR"
  mkdir -p "$summary_dir"
  summary_tmp="$(mktemp "$summary_dir/.acp-summary.XXXXXX")"
  {
    printf '{\n'
    printf '  "schemaVersion": "%s",\n' "$(json_escape "$SUMMARY_SCHEMA_VERSION")"
    printf '  "runId": "%s",\n' "$(json_escape "$SUITE_RUN_ID")"
    printf '  "gitHead": "%s",\n' "$(json_escape "$GIT_HEAD")"
    printf '  "gitDirty": %s,\n' "$GIT_DIRTY"
    printf '  "host": {\n'
    printf '    "name": "%s",\n' "$(json_escape "$HOST_NAME")"
    printf '    "os": "%s",\n' "$(json_escape "$HOST_OS")"
    printf '    "arch": "%s"\n' "$(json_escape "$HOST_ARCH")"
    printf '  },\n'
    printf '  "result": "%s",\n' "$(json_escape "$SUITE_RESULT")"
    printf '  "startedAtUtc": "%s",\n' "$(json_escape "$SUITE_STARTED_AT_UTC")"
    printf '  "finishedAtUtc": "%s",\n' "$(json_escape "$finished_at_utc")"
    printf '  "durationSeconds": %s,\n' "$duration_seconds"
    printf '  "stageCounts": {\n'
    printf '    "total": %s,\n' "$count_total"
    printf '    "pass": %s,\n' "$count_pass"
    printf '    "fail": %s,\n' "$count_fail"
    printf '    "warn": %s,\n' "$count_warn"
    printf '    "skipped": %s\n' "$count_skipped"
    printf '  },\n'
    printf '  "strictCodexProbes": %s,\n' "$STRICT_CODEX_PROBES"
    printf '  "runCodexProbes": %s,\n' "${RUN_CODEX_PROBES:-0}"
    printf '  "config": {\n'
    printf '    "portBase": %s,\n' "$PORT_BASE"
    printf '    "codexProbeRetries": %s,\n' "$CODEX_PROBE_RETRIES"
    printf '    "codexProbeRetryDelaySeconds": %s,\n' "$CODEX_PROBE_RETRY_DELAY_SECONDS"
    printf '    "strictCodexProbes": %s,\n' "$STRICT_CODEX_PROBES"
    printf '    "runCodexProbes": %s\n' "${RUN_CODEX_PROBES:-0}"
    printf '  },\n'
    printf '  "artifacts": {\n'
    printf '    "suiteLogDir": "%s"\n' "$(json_escape "$SUITE_LOG_DIR")"
    printf '  },\n'
    printf '  "stages": [\n'
    local first=1
    while IFS='|' read -r index stage status required exit_code started_at_utc finished_at_utc duration_seconds attempts message log_path; do
      [ -z "$index" ] && continue
      if [ "$first" -eq 0 ]; then
        printf ',\n'
      fi
      first=0
      printf '    {"index":%s,"stage":"%s","status":"%s","required":%s,"exitCode":%s,"startedAtUtc":"%s","finishedAtUtc":"%s","durationSeconds":%s,"attempts":%s,"message":"%s","logPath":"%s"}' \
        "$index" \
        "$(json_escape "$stage")" \
        "$(json_escape "$status")" \
        "$required" \
        "$exit_code" \
        "$(json_escape "$started_at_utc")" \
        "$(json_escape "$finished_at_utc")" \
        "$duration_seconds" \
        "$attempts" \
        "$(json_escape "$message")" \
        "$(json_escape "$log_path")"
    done <<< "$SUMMARY_LINES"
    printf '\n  ]\n'
    printf '}\n'
  } > "$summary_tmp"
  mv "$summary_tmp" "$SUMMARY_JSON_PATH"

  # Lightweight guard against accidental format drift.
  if ! rg -q '"schemaVersion":' "$SUMMARY_JSON_PATH" || \
     ! rg -q '"stageCounts": \{' "$SUMMARY_JSON_PATH" || \
     ! rg -q '"artifacts": \{' "$SUMMARY_JSON_PATH" || \
     ! rg -q '"stages": \[' "$SUMMARY_JSON_PATH" || \
     ! rg -q '"logPath":' "$SUMMARY_JSON_PATH"; then
    echo "summary json validation failed: missing required fields" >&2
    return 1
  fi
}

trap write_summary_json EXIT

run_with_retry() {
  local cmd="$1"
  local label="$2"
  local max_attempts="${3:-2}"
  local delay_seconds="${4:-0}"
  local log_path="${5:-}"
  local attempt=1
  local exit_code=0

  RETRY_LAST_ATTEMPTS=0
  RETRY_LAST_EXIT_CODE=0
  while [ "$attempt" -le "$max_attempts" ]; do
    if [ -n "$log_path" ]; then
      {
        echo "[attempt ${attempt}/${max_attempts}] $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "$ $cmd"
      } >> "$log_path"
    fi
    set +e
    if [ -n "$log_path" ]; then
      eval "$cmd" > >(tee -a "$log_path") 2> >(tee -a "$log_path" >&2)
    else
      eval "$cmd"
    fi
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
  local started_at_utc
  local ended_at_epoch
  local finished_at_utc
  local duration_seconds
  local log_path="${SUITE_LOG_DIR}/${index}_${stage}.log"
  mkdir -p "$SUITE_LOG_DIR"
  : > "$log_path"
  {
    echo "[attempt 1/1] $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "$ $cmd"
  } >> "$log_path"
  started_at_epoch="$(date +%s)"
  started_at_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "$label"
  set +e
  eval "$cmd" > >(tee -a "$log_path") 2> >(tee -a "$log_path" >&2)
  local exit_code=$?
  set -e
  ended_at_epoch="$(date +%s)"
  finished_at_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  duration_seconds="$((ended_at_epoch - started_at_epoch))"
  if [ "$exit_code" -eq 0 ]; then
    append_summary "$index" "$stage" "pass" "true" "$exit_code" "$started_at_utc" "$finished_at_utc" "$duration_seconds" "1" "ok" "$log_path"
    return 0
  fi
  append_summary "$index" "$stage" "fail" "true" "$exit_code" "$started_at_utc" "$finished_at_utc" "$duration_seconds" "1" "required stage failed" "$log_path"
  return "$exit_code"
}

run_optional_stage() {
  local index="$1"
  local stage="$2"
  local label="$3"
  local cmd="$4"
  local started_at_epoch
  local started_at_utc
  local ended_at_epoch
  local finished_at_utc
  local duration_seconds
  local log_path="${SUITE_LOG_DIR}/${index}_${stage}.log"
  mkdir -p "$SUITE_LOG_DIR"
  : > "$log_path"
  started_at_epoch="$(date +%s)"
  started_at_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "$label"
  if run_with_retry "$cmd" "$stage" "$CODEX_PROBE_RETRIES" "$CODEX_PROBE_RETRY_DELAY_SECONDS" "$log_path"; then
    ended_at_epoch="$(date +%s)"
    finished_at_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    duration_seconds="$((ended_at_epoch - started_at_epoch))"
    append_summary "$index" "$stage" "pass" "false" "0" "$started_at_utc" "$finished_at_utc" "$duration_seconds" "$RETRY_LAST_ATTEMPTS" "ok" "$log_path"
    return 0
  fi
  ended_at_epoch="$(date +%s)"
  finished_at_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  duration_seconds="$((ended_at_epoch - started_at_epoch))"
  if [ "$STRICT_CODEX_PROBES" = "1" ]; then
    append_summary "$index" "$stage" "fail" "false" "$RETRY_LAST_EXIT_CODE" "$started_at_utc" "$finished_at_utc" "$duration_seconds" "$RETRY_LAST_ATTEMPTS" "failed under strict mode" "$log_path"
    echo "[suite] FAIL ${stage} failed under strict mode"
    return 1
  fi
  append_summary "$index" "$stage" "warn" "false" "$RETRY_LAST_EXIT_CODE" "$started_at_utc" "$finished_at_utc" "$duration_seconds" "$RETRY_LAST_ATTEMPTS" "failed but allowed in non-strict mode" "$log_path"
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
  append_summary "6" "codex_permission_probe" "skipped" "false" "0" "$SUITE_STARTED_AT_UTC" "$SUITE_STARTED_AT_UTC" "0" "0" "skipped (RUN_CODEX_PROBES=0)" ""
  append_summary "7" "codex_multiturn_smoke" "skipped" "false" "0" "$SUITE_STARTED_AT_UTC" "$SUITE_STARTED_AT_UTC" "0" "0" "skipped (RUN_CODEX_PROBES=0)" ""
fi

SUITE_RESULT="pass"
echo "[suite] PASS"
