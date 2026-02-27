#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

OUT_FILE="${ACP_UPSTREAM_DAILY_FILE:-docs-dev/ops/acp-upstream-daily.md}"
SINCE_DAYS="${ACP_UPSTREAM_SINCE_DAYS:-1}"
ORG="${ACP_UPSTREAM_ORG:-agentclientprotocol}"
DATE_UTC="$(date -u +"%Y-%m-%d")"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required (https://cli.github.com/)" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

repos=(
  "agentclientprotocol/spec"
  "agentclientprotocol/kotlin-sdk"
  "agentclientprotocol/swift-sdk"
  "agentclientprotocol/python-sdk"
  "agentclientprotocol/typescript-sdk"
  "agentclientprotocol/go-sdk"
  "agentclientprotocol/rust-sdk"
)

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

method_values() {
  local meta_file="$1"
  jq -r '.agentMethods[]?, .clientMethods[]?, .protocolMethods[]?' "$meta_file" | sort -u
}

method_count() {
  local file="$1"
  wc -l < "$file" | tr -d ' '
}

symbol_to_method_value() {
  local symbol="$1"
  rg "public static let ${symbol} = \"([^\"]+)\"" -or '$1' "Sources/SKIACP/ACPMethods.swift" | head -n1
}

upstream_meta_file="$tmp_dir/upstream-meta.json"
upstream_unstable_meta_file="$tmp_dir/upstream-meta.unstable.json"
local_meta_file="Tests/SKIntelligenceTests/Fixtures/acp-schema-meta/meta.json"
local_unstable_meta_file="Tests/SKIntelligenceTests/Fixtures/acp-schema-meta/meta.unstable.json"

stable_up_methods="$tmp_dir/stable-up.methods"
stable_local_methods="$tmp_dir/stable-local.methods"
unstable_up_methods="$tmp_dir/unstable-up.methods"
unstable_local_methods="$tmp_dir/unstable-local.methods"

stable_missing_in_local="$tmp_dir/stable.missing-in-local"
stable_extra_in_local="$tmp_dir/stable.extra-in-local"
unstable_missing_in_local="$tmp_dir/unstable.missing-in-local"
unstable_extra_in_local="$tmp_dir/unstable.extra-in-local"
compatibility_methods="$tmp_dir/compatibility.methods"
compatibility_overlap="$tmp_dir/compatibility.overlap"

curl -fsSL "https://raw.githubusercontent.com/agentclientprotocol/agent-client-protocol/main/schema/meta.json" -o "$upstream_meta_file"
curl -fsSL "https://raw.githubusercontent.com/agentclientprotocol/agent-client-protocol/main/schema/meta.unstable.json" -o "$upstream_unstable_meta_file"

method_values "$upstream_meta_file" > "$stable_up_methods"
method_values "$local_meta_file" > "$stable_local_methods"
method_values "$upstream_unstable_meta_file" > "$unstable_up_methods"
method_values "$local_unstable_meta_file" > "$unstable_local_methods"

comm -23 "$stable_up_methods" "$stable_local_methods" > "$stable_missing_in_local" || true
comm -13 "$stable_up_methods" "$stable_local_methods" > "$stable_extra_in_local" || true
comm -23 "$unstable_up_methods" "$unstable_local_methods" > "$unstable_missing_in_local" || true
comm -13 "$unstable_up_methods" "$unstable_local_methods" > "$unstable_extra_in_local" || true

while IFS= read -r symbol; do
  [ -z "$symbol" ] && continue
  value="$(symbol_to_method_value "$symbol" || true)"
  [ -n "$value" ] && echo "$value"
done < <(
  sed -n '/compatibilityExtensions:/,/]/p' "Sources/SKIACP/ACPMethodCatalog.swift" \
    | rg -o 'ACPMethods\.([A-Za-z0-9_]+)' -r '$1' \
    | sort -u
) | sort -u > "$compatibility_methods"

cat "$stable_up_methods" "$unstable_up_methods" | sort -u > "$tmp_dir/upstream-all.methods"
comm -12 "$compatibility_methods" "$tmp_dir/upstream-all.methods" > "$compatibility_overlap" || true

repos_file="$tmp_dir/repos.txt"
printf '%s\n' "${repos[@]}" | sort -u > "$repos_file"

# Expand watcher list with current org repositories.
gh api "/orgs/${ORG}/repos?per_page=100&type=all" --jq '.[].full_name' \
  2>/dev/null | sort -u >> "$repos_file" || true
sort -u "$repos_file" -o "$repos_file"

{
  echo "# ACP Upstream Daily Watch"
  echo
  echo "- Date (UTC): ${DATE_UTC}"
  echo "- Generated At: ${NOW_UTC}"
  echo "- Source Org: ${ORG}"
  echo "- Window: last ${SINCE_DAYS} day(s)"
  echo
  echo "## Summary"
  echo
} > "$tmp_dir/report.md"
repo_sections="$tmp_dir/repositories.md"
> "$repo_sections"

total_repos=0
p0_hits=0
p1_hits=0
p2_hits=0

while IFS= read -r repo; do
  [ -z "$repo" ] && continue
  total_repos=$((total_repos + 1))

  repo_json="$tmp_dir/repo.json"
  if ! gh api "/repos/${repo}" > "$repo_json" 2>/dev/null; then
    continue
  fi

  default_branch="$(jq -r '.default_branch // "main"' "$repo_json")"
  pushed_at="$(jq -r '.pushed_at // "unknown"' "$repo_json")"
  html_url="$(jq -r '.html_url // "https://github.com/'"$repo"'"' "$repo_json")"

  head_sha="$(gh api "/repos/${repo}/commits/${default_branch}" --jq '.sha' 2>/dev/null | cut -c1-12 || echo "unknown")"

  release_json="$tmp_dir/release-${repo//\//_}.json"
  if gh api "/repos/${repo}/releases/latest" > "$release_json" 2>/dev/null; then
    :
  else
    echo '{}' > "$release_json"
  fi
  release_tag="$(jq -r '.tag_name // "none"' "$release_json")"
  release_time="$(jq -r '.published_at // "none"' "$release_json")"

  prs_file="$tmp_dir/prs-${repo//\//_}.json"
  issues_file="$tmp_dir/issues-${repo//\//_}.json"
  gh api "/repos/${repo}/pulls?state=all&sort=updated&direction=desc&per_page=20" > "$prs_file" 2>/dev/null || echo '[]' > "$prs_file"
  gh api "/repos/${repo}/issues?state=all&sort=updated&direction=desc&per_page=20" > "$issues_file" 2>/dev/null || echo '[]' > "$issues_file"

  # P0/P1/P2 keyword scan (title/body).
  p0_count="$(jq --argjson days "$SINCE_DAYS" '
    [ .[] | select((now - (.updated_at|fromdateiso8601)) <= ($days*86400))
      | select(((.title // "") + " " + (.body // "")) | test("breaking|deprecat|protocol|schema|json-rpc|transport"; "i")) ] | length
  ' "$prs_file")"
  p1_count="$(jq --argjson days "$SINCE_DAYS" '
    [ .[] | select((now - (.updated_at|fromdateiso8601)) <= ($days*86400))
      | select(((.title // "") + " " + (.body // "")) | test("sdk|client|server|example|tool|session|permission"; "i")) ] | length
  ' "$prs_file")"
  p2_count="$(jq --argjson days "$SINCE_DAYS" '
    [ .[] | select((now - (.updated_at|fromdateiso8601)) <= ($days*86400))
      | select(((.title // "") + " " + (.body // "")) | test("doc|readme|typo|format|chore"; "i")) ] | length
  ' "$prs_file")"

  p0_hits=$((p0_hits + p0_count))
  p1_hits=$((p1_hits + p1_count))
  p2_hits=$((p2_hits + p2_count))

  {
    echo "### ${repo}"
    echo
    echo "- URL: ${html_url}"
    echo "- Default Branch: \`${default_branch}\`"
    echo "- Head SHA: \`${head_sha}\`"
    echo "- Pushed At: ${pushed_at}"
    echo "- Latest Release: ${release_tag} (${release_time})"
    echo "- Risk Signal: P0=${p0_count}, P1=${p1_count}, P2=${p2_count}"
    echo "- Recent PRs: https://github.com/${repo}/pulls?q=sort%3Aupdated-desc"
    echo "- Recent Issues: https://github.com/${repo}/issues?q=sort%3Aupdated-desc"
    echo
  } >> "$repo_sections"
done < "$repos_file"

{
  cat "$tmp_dir/report.md"
  echo "- Repositories Watched: ${total_repos}"
  echo "- Aggregate Risk Signal: P0=${p0_hits}, P1=${p1_hits}, P2=${p2_hits}"
  echo "- Schema Drift (stable): missingLocal=$(method_count "$stable_missing_in_local"), extraLocal=$(method_count "$stable_extra_in_local")"
  echo "- Schema Drift (unstable): missingLocal=$(method_count "$unstable_missing_in_local"), extraLocal=$(method_count "$unstable_extra_in_local")"
  echo "- Compatibility Overlap With Upstream: $(method_count "$compatibility_overlap")"
  if [ "$p0_hits" -gt 0 ]; then
    echo "- Action: trigger same-day P0 assessment and regression update."
  elif [ "$p1_hits" -gt 0 ]; then
    echo "- Action: include P1 items in weekly alignment."
  else
    echo "- Action: no immediate protocol-risk follow-up."
  fi
  echo
  echo "## Schema Drift"
  echo
  echo "- Upstream schema source:"
  echo "  - stable: https://raw.githubusercontent.com/agentclientprotocol/agent-client-protocol/main/schema/meta.json"
  echo "  - unstable: https://raw.githubusercontent.com/agentclientprotocol/agent-client-protocol/main/schema/meta.unstable.json"
  echo "- Stable methods: upstream=$(method_count "$stable_up_methods"), local=$(method_count "$stable_local_methods"), missingLocal=$(method_count "$stable_missing_in_local"), extraLocal=$(method_count "$stable_extra_in_local")"
  echo "- Unstable methods: upstream=$(method_count "$unstable_up_methods"), local=$(method_count "$unstable_local_methods"), missingLocal=$(method_count "$unstable_missing_in_local"), extraLocal=$(method_count "$unstable_extra_in_local")"
  echo
  echo "### Stable Missing In Local"
  if [ -s "$stable_missing_in_local" ]; then sed 's/^/- /' "$stable_missing_in_local"; else echo "- none"; fi
  echo
  echo "### Stable Extra In Local"
  if [ -s "$stable_extra_in_local" ]; then sed 's/^/- /' "$stable_extra_in_local"; else echo "- none"; fi
  echo
  echo "### Unstable Missing In Local"
  if [ -s "$unstable_missing_in_local" ]; then sed 's/^/- /' "$unstable_missing_in_local"; else echo "- none"; fi
  echo
  echo "### Unstable Extra In Local"
  if [ -s "$unstable_extra_in_local" ]; then sed 's/^/- /' "$unstable_extra_in_local"; else echo "- none"; fi
  echo
  echo "### Compatibility Extensions"
  if [ -s "$compatibility_methods" ]; then sed 's/^/- /' "$compatibility_methods"; else echo "- none"; fi
  echo
  echo "### Compatibility Overlap With Upstream"
  if [ -s "$compatibility_overlap" ]; then
    sed 's/^/- /' "$compatibility_overlap"
    echo
    echo "- Action: migrate overlapped methods from compatibilityExtensions into official baselines."
  else
    echo "- none"
  fi
  echo
  echo "## Repositories"
  echo
  cat "$repo_sections"
} > "$OUT_FILE"

echo "Wrote upstream watch report: ${OUT_FILE}"
