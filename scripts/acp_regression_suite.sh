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
SUMMARY_GENERATED_BY="scripts/acp_regression_suite.sh@1"
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
FAILURE_STAGE=""
FAILURE_EXIT_CODE=0

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

json_array_from_lines() {
  local lines="$1"
  local first=1
  local item
  printf '['
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s"' "$(json_escape "$item")"
  done <<< "$lines"
  printf ']'
}

json_object_stage_status_map() {
  local lines="$1"
  local first=1
  local row
  local stage
  local status
  printf '{'
  while IFS='|' read -r _index stage status _required _exit_code _started_at_utc _finished_at_utc _duration_seconds _attempts _message _log_path; do
    [ -z "$stage" ] && continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s":"%s"' "$(json_escape "$stage")" "$(json_escape "$status")"
  done <<< "$lines"
  printf '}'
}

json_object_stage_exit_code_map() {
  local lines="$1"
  local first=1
  local stage
  local exit_code
  printf '{'
  while IFS='|' read -r _index stage _status _required exit_code _started_at_utc _finished_at_utc _duration_seconds _attempts _message _log_path; do
    [ -z "$stage" ] && continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s":%s' "$(json_escape "$stage")" "$exit_code"
  done <<< "$lines"
  printf '}'
}

json_object_stage_duration_map() {
  local lines="$1"
  local first=1
  local stage
  local duration_seconds
  printf '{'
  while IFS='|' read -r _index stage _status _required _exit_code _started_at_utc _finished_at_utc duration_seconds _attempts _message _log_path; do
    [ -z "$stage" ] && continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s":%s' "$(json_escape "$stage")" "$duration_seconds"
  done <<< "$lines"
  printf '}'
}

json_object_stage_attempts_map() {
  local lines="$1"
  local first=1
  local stage
  local attempts
  printf '{'
  while IFS='|' read -r _index stage _status _required _exit_code _started_at_utc _finished_at_utc _duration_seconds attempts _message _log_path; do
    [ -z "$stage" ] && continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s":%s' "$(json_escape "$stage")" "$attempts"
  done <<< "$lines"
  printf '}'
}

json_object_stage_message_map() {
  local lines="$1"
  local first=1
  local stage
  local message
  printf '{'
  while IFS='|' read -r _index stage _status _required _exit_code _started_at_utc _finished_at_utc _duration_seconds _attempts message _log_path; do
    [ -z "$stage" ] && continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s":"%s"' "$(json_escape "$stage")" "$(json_escape "$message")"
  done <<< "$lines"
  printf '}'
}

json_object_stage_log_path_map() {
  local lines="$1"
  local first=1
  local stage
  local log_path
  printf '{'
  while IFS='|' read -r _index stage _status _required _exit_code _started_at_utc _finished_at_utc _duration_seconds _attempts _message log_path; do
    [ -z "$stage" ] && continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s":"%s"' "$(json_escape "$stage")" "$(json_escape "$log_path")"
  done <<< "$lines"
  printf '}'
}

json_object_stage_required_map() {
  local lines="$1"
  local first=1
  local stage
  local required
  printf '{'
  while IFS='|' read -r _index stage _status required _exit_code _started_at_utc _finished_at_utc _duration_seconds _attempts _message _log_path; do
    [ -z "$stage" ] && continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s":%s' "$(json_escape "$stage")" "$required"
  done <<< "$lines"
  printf '}'
}

json_object_stage_started_at_map() {
  local lines="$1"
  local first=1
  local stage
  local started_at_utc
  printf '{'
  while IFS='|' read -r _index stage _status _required _exit_code started_at_utc _finished_at_utc _duration_seconds _attempts _message _log_path; do
    [ -z "$stage" ] && continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s":"%s"' "$(json_escape "$stage")" "$(json_escape "$started_at_utc")"
  done <<< "$lines"
  printf '}'
}

json_object_stage_finished_at_map() {
  local lines="$1"
  local first=1
  local stage
  local finished_at_utc
  printf '{'
  while IFS='|' read -r _index stage _status _required _exit_code _started_at_utc finished_at_utc _duration_seconds _attempts _message _log_path; do
    [ -z "$stage" ] && continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s":"%s"' "$(json_escape "$stage")" "$(json_escape "$finished_at_utc")"
  done <<< "$lines"
  printf '}'
}

json_object_stage_index_map() {
  local lines="$1"
  local first=1
  local index
  local stage
  printf '{'
  while IFS='|' read -r index stage _status _required _exit_code _started_at_utc _finished_at_utc _duration_seconds _attempts _message _log_path; do
    [ -z "$stage" ] && continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s":%s' "$(json_escape "$stage")" "$index"
  done <<< "$lines"
  printf '}'
}

json_array_required_failed_stages() {
  local lines="$1"
  local first=1
  local stage
  local status
  local required
  printf '['
  while IFS='|' read -r _index stage status required _exit_code _started_at_utc _finished_at_utc _duration_seconds _attempts _message _log_path; do
    [ -z "$stage" ] && continue
    if [ "$required" != "true" ] || [ "$status" = "pass" ]; then
      continue
    fi
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s"' "$(json_escape "$stage")"
  done <<< "$lines"
  printf ']'
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

record_failure() {
  local stage="$1"
  local exit_code="$2"
  if [ -z "$FAILURE_STAGE" ]; then
    FAILURE_STAGE="$stage"
    FAILURE_EXIT_CODE="$exit_code"
  fi
}

write_summary_json() {
  local suite_exit_code="$?"
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
  local required_total=0
  local required_pass=0
  local required_fail=0
  local optional_total=0
  local optional_pass=0
  local optional_fail=0
  local optional_warn=0
  local optional_skipped=0
  local required_failed=0
  local counts_consistent="true"
  local ci_recommendation="fail"
  local result_reason="required stages failed"
  local probe_mode="disabled"
  local summary_hash="unavailable"
  local failed_stages=""
  local non_pass_stages=""
  local warn_stages=""
  local skipped_stages=""
  finished_at_epoch="$(date +%s)"
  finished_at_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  duration_seconds="$((finished_at_epoch - SUITE_STARTED_AT_EPOCH))"
  while IFS='|' read -r _index _stage _status _required _exit_code _started_at_utc _finished_at_utc _duration_seconds _attempts _message _log_path; do
    [ -z "$_index" ] && continue
    count_total=$((count_total + 1))
    if [ "$_status" != "pass" ]; then
      non_pass_stages+="${_stage}"$'\n'
    fi
    if [ "$_status" = "fail" ]; then
      failed_stages+="${_stage}"$'\n'
    fi
    if [ "$_status" = "warn" ]; then
      warn_stages+="${_stage}"$'\n'
    fi
    if [ "$_status" = "skipped" ]; then
      skipped_stages+="${_stage}"$'\n'
    fi
    if [ "$_required" = "true" ]; then
      required_total=$((required_total + 1))
      case "$_status" in
        pass) required_pass=$((required_pass + 1)) ;;
        *) required_fail=$((required_fail + 1)); required_failed=$((required_failed + 1)) ;;
      esac
    else
      optional_total=$((optional_total + 1))
      case "$_status" in
        pass) optional_pass=$((optional_pass + 1)) ;;
        fail) optional_fail=$((optional_fail + 1)) ;;
        warn) optional_warn=$((optional_warn + 1)) ;;
        skipped) optional_skipped=$((optional_skipped + 1)) ;;
      esac
    fi
    case "$_status" in
      pass) count_pass=$((count_pass + 1)) ;;
      fail) count_fail=$((count_fail + 1)) ;;
      warn) count_warn=$((count_warn + 1)) ;;
      skipped) count_skipped=$((count_skipped + 1)) ;;
    esac
  done <<< "$SUMMARY_LINES"
  if [ "$count_total" -ne $((count_pass + count_fail + count_warn + count_skipped)) ] || \
     [ "$count_total" -ne $((required_total + optional_total)) ] || \
     [ "$required_total" -ne $((required_pass + required_fail)) ] || \
     [ "$optional_total" -ne $((optional_pass + optional_fail + optional_warn + optional_skipped)) ]; then
    counts_consistent="false"
  fi
  if [ "$required_failed" -gt 0 ] || [ "$count_fail" -gt 0 ]; then
    ci_recommendation="fail"
    result_reason="required stages failed"
  elif [ "$count_warn" -gt 0 ] || [ "$count_skipped" -gt 0 ]; then
    ci_recommendation="pass_with_warnings"
    result_reason="optional stages warned or skipped"
  else
    ci_recommendation="pass"
    result_reason="all stages passed"
  fi
  if [ "${RUN_CODEX_PROBES:-0}" = "1" ]; then
    if [ "$STRICT_CODEX_PROBES" = "1" ]; then
      probe_mode="strict"
    else
      probe_mode="non_strict"
    fi
  fi
  if command -v shasum >/dev/null 2>&1; then
    summary_hash="$(printf '%s|%s|%s|%s|%s|%s|%s\n%s\n' \
      "$SUITE_RUN_ID" \
      "$GIT_HEAD" \
      "$PORT_BASE" \
      "$CODEX_PROBE_RETRIES" \
      "$CODEX_PROBE_RETRY_DELAY_SECONDS" \
      "$STRICT_CODEX_PROBES" \
      "${RUN_CODEX_PROBES:-0}" \
      "$SUMMARY_LINES" | shasum -a 256 | awk '{print $1}')"
  fi
  summary_dir="$(dirname "$SUMMARY_JSON_PATH")"
  mkdir -p "$SUITE_LOG_DIR"
  mkdir -p "$summary_dir"
  summary_tmp="$(mktemp "$summary_dir/.acp-summary.XXXXXX")"
  {
    printf '{\n'
    printf '  "schemaVersion": "%s",\n' "$(json_escape "$SUMMARY_SCHEMA_VERSION")"
    printf '  "generatedBy": "%s",\n' "$(json_escape "$SUMMARY_GENERATED_BY")"
    printf '  "runId": "%s",\n' "$(json_escape "$SUITE_RUN_ID")"
    printf '  "summaryHash": "%s",\n' "$(json_escape "$summary_hash")"
    printf '  "gitHead": "%s",\n' "$(json_escape "$GIT_HEAD")"
    printf '  "gitDirty": %s,\n' "$GIT_DIRTY"
    printf '  "host": {\n'
    printf '    "name": "%s",\n' "$(json_escape "$HOST_NAME")"
    printf '    "os": "%s",\n' "$(json_escape "$HOST_OS")"
    printf '    "arch": "%s"\n' "$(json_escape "$HOST_ARCH")"
    printf '  },\n'
    printf '  "result": "%s",\n' "$(json_escape "$SUITE_RESULT")"
    printf '  "exitCode": %s,\n' "$suite_exit_code"
    if [ -n "$FAILURE_STAGE" ]; then
      printf '  "failure": {"stage":"%s","exitCode":%s},\n' "$(json_escape "$FAILURE_STAGE")" "$FAILURE_EXIT_CODE"
    else
      printf '  "failure": null,\n'
    fi
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
    printf '  "failedStages": %s,\n' "$(json_array_from_lines "$failed_stages")"
    printf '  "nonPassStages": %s,\n' "$(json_array_from_lines "$non_pass_stages")"
    printf '  "warnStages": %s,\n' "$(json_array_from_lines "$warn_stages")"
    printf '  "skippedStages": %s,\n' "$(json_array_from_lines "$skipped_stages")"
    printf '  "requiredFailedStages": %s,\n' "$(json_array_required_failed_stages "$SUMMARY_LINES")"
    printf '  "stageStatusMap": %s,\n' "$(json_object_stage_status_map "$SUMMARY_LINES")"
    printf '  "stageExitCodeMap": %s,\n' "$(json_object_stage_exit_code_map "$SUMMARY_LINES")"
    printf '  "stageDurationSecondsMap": %s,\n' "$(json_object_stage_duration_map "$SUMMARY_LINES")"
    printf '  "stageAttemptsMap": %s,\n' "$(json_object_stage_attempts_map "$SUMMARY_LINES")"
    printf '  "stageMessageMap": %s,\n' "$(json_object_stage_message_map "$SUMMARY_LINES")"
    printf '  "stageLogPathMap": %s,\n' "$(json_object_stage_log_path_map "$SUMMARY_LINES")"
    printf '  "stageRequiredMap": %s,\n' "$(json_object_stage_required_map "$SUMMARY_LINES")"
    printf '  "stageStartedAtMap": %s,\n' "$(json_object_stage_started_at_map "$SUMMARY_LINES")"
    printf '  "stageFinishedAtMap": %s,\n' "$(json_object_stage_finished_at_map "$SUMMARY_LINES")"
    printf '  "stageIndexMap": %s,\n' "$(json_object_stage_index_map "$SUMMARY_LINES")"
    printf '  "probeMode": "%s",\n' "$(json_escape "$probe_mode")"
    printf '  "ciRecommendation": "%s",\n' "$(json_escape "$ci_recommendation")"
    printf '  "resultReason": "%s",\n' "$(json_escape "$result_reason")"
    if [ "$count_total" -eq "$count_pass" ]; then
      printf '  "allStagesPassed": true,\n'
    else
      printf '  "allStagesPassed": false,\n'
    fi
    if [ "$count_warn" -gt 0 ]; then
      printf '  "hasWarnings": true,\n'
    else
      printf '  "hasWarnings": false,\n'
    fi
    if [ "$count_skipped" -gt 0 ]; then
      printf '  "hasSkipped": true,\n'
    else
      printf '  "hasSkipped": false,\n'
    fi
    printf '  "countsConsistent": %s,\n' "$counts_consistent"
    printf '  "requiredStageCounts": {\n'
    printf '    "total": %s,\n' "$required_total"
    printf '    "pass": %s,\n' "$required_pass"
    printf '    "fail": %s\n' "$required_fail"
    printf '  },\n'
    printf '  "optionalStageCounts": {\n'
    printf '    "total": %s,\n' "$optional_total"
    printf '    "pass": %s,\n' "$optional_pass"
    printf '    "fail": %s,\n' "$optional_fail"
    printf '    "warn": %s,\n' "$optional_warn"
    printf '    "skipped": %s\n' "$optional_skipped"
    printf '  },\n'
    if [ "$required_failed" -eq 0 ]; then
      printf '  "requiredPassed": true,\n'
    else
      printf '  "requiredPassed": false,\n'
    fi
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

  # Prefer structural validation when jq is available; fall back to text guards.
  if command -v jq >/dev/null 2>&1; then
    if ! jq -e '
      (.schemaVersion | type == "string") and
      (.generatedBy | type == "string") and
      (.summaryHash | type == "string") and
      (.exitCode | type == "number") and
      (.stageCounts | type == "object") and
      (.failedStages | type == "array") and
      (.nonPassStages | type == "array") and
      (.warnStages | type == "array") and
      (.skippedStages | type == "array") and
      (.requiredFailedStages | type == "array") and
      (.stageStatusMap | type == "object") and
      (.stageExitCodeMap | type == "object") and
      (.stageDurationSecondsMap | type == "object") and
      (.stageAttemptsMap | type == "object") and
      (.stageMessageMap | type == "object") and
      (.stageLogPathMap | type == "object") and
      (.stageRequiredMap | type == "object") and
      (.stageStartedAtMap | type == "object") and
      (.stageFinishedAtMap | type == "object") and
      (.stageIndexMap | type == "object") and
      (.probeMode | type == "string") and
      (.ciRecommendation | type == "string") and
      (.resultReason | type == "string") and
      (.allStagesPassed | type == "boolean") and
      (.hasWarnings | type == "boolean") and
      (.hasSkipped | type == "boolean") and
      (.countsConsistent | type == "boolean") and
      (.requiredStageCounts | type == "object") and
      (.optionalStageCounts | type == "object") and
      (.requiredPassed | type == "boolean") and
      (.artifacts | type == "object") and
      (.stages | type == "array") and
      (.stages | length >= 1) and
      (.stages[0].logPath != null)
    ' "$SUMMARY_JSON_PATH" >/dev/null; then
      echo "summary json validation failed: jq structural check failed" >&2
      return 1
    fi
  else
    if ! rg -q '"schemaVersion":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"generatedBy":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"summaryHash":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"exitCode":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"failure":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"stageCounts": \{' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"failedStages":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"nonPassStages":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"warnStages":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"skippedStages":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"requiredFailedStages":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"stageStatusMap":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"stageExitCodeMap":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"stageDurationSecondsMap":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"stageAttemptsMap":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"stageMessageMap":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"stageLogPathMap":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"stageRequiredMap":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"stageStartedAtMap":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"stageFinishedAtMap":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"stageIndexMap":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"probeMode":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"ciRecommendation":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"resultReason":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"allStagesPassed":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"hasWarnings":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"hasSkipped":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"countsConsistent":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"requiredStageCounts": \{' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"optionalStageCounts": \{' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"requiredPassed":' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"artifacts": \{' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"stages": \[' "$SUMMARY_JSON_PATH" || \
       ! rg -q '"logPath":' "$SUMMARY_JSON_PATH"; then
      echo "summary json validation failed: missing required fields" >&2
      return 1
    fi
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
  record_failure "$stage" "$exit_code"
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
    record_failure "$stage" "$RETRY_LAST_EXIT_CODE"
    echo "[suite] FAIL ${stage} failed under strict mode"
    return 1
  fi
  append_summary "$index" "$stage" "warn" "false" "$RETRY_LAST_EXIT_CODE" "$started_at_utc" "$finished_at_utc" "$duration_seconds" "$RETRY_LAST_ATTEMPTS" "failed but allowed in non-strict mode" "$log_path"
  echo "[suite] WARN ${stage} exhausted retries (continuing)"
  return 0
}

print_stage_counts_line() {
  local count_total=0
  local count_pass=0
  local count_fail=0
  local count_warn=0
  local count_skipped=0
  local required_failed=0
  local ci_recommendation="fail"
  while IFS='|' read -r _index _stage _status _required _exit_code _started_at_utc _finished_at_utc _duration_seconds _attempts _message _log_path; do
    [ -z "$_index" ] && continue
    count_total=$((count_total + 1))
    if [ "$_required" = "true" ] && [ "$_status" != "pass" ]; then
      required_failed=$((required_failed + 1))
    fi
    case "$_status" in
      pass) count_pass=$((count_pass + 1)) ;;
      fail) count_fail=$((count_fail + 1)) ;;
      warn) count_warn=$((count_warn + 1)) ;;
      skipped) count_skipped=$((count_skipped + 1)) ;;
    esac
  done <<< "$SUMMARY_LINES"
  if [ "$required_failed" -gt 0 ] || [ "$count_fail" -gt 0 ]; then
    ci_recommendation="fail"
  elif [ "$count_warn" -gt 0 ] || [ "$count_skipped" -gt 0 ]; then
    ci_recommendation="pass_with_warnings"
  else
    ci_recommendation="pass"
  fi
  if [ "$required_failed" -eq 0 ]; then
    echo "[suite] counts total=${count_total} pass=${count_pass} fail=${count_fail} warn=${count_warn} skipped=${count_skipped} requiredPassed=true ciRecommendation=${ci_recommendation} runCodexProbes=${RUN_CODEX_PROBES:-0} strictCodexProbes=${STRICT_CODEX_PROBES}"
  else
    echo "[suite] counts total=${count_total} pass=${count_pass} fail=${count_fail} warn=${count_warn} skipped=${count_skipped} requiredPassed=false ciRecommendation=${ci_recommendation} runCodexProbes=${RUN_CODEX_PROBES:-0} strictCodexProbes=${STRICT_CODEX_PROBES}"
  fi
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
print_stage_counts_line
echo "[suite] PASS"
