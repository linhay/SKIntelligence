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

  release_tag="$(gh api "/repos/${repo}/releases/latest" --jq '.tag_name' 2>/dev/null || echo "none")"
  release_time="$(gh api "/repos/${repo}/releases/latest" --jq '.published_at' 2>/dev/null || echo "none")"

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
  } >> "$tmp_dir/report.md"
done < "$repos_file"

# Insert summary block right after "## Summary"
summary_block="$tmp_dir/summary.md"
{
  echo "- Repositories Watched: ${total_repos}"
  echo "- Aggregate Risk Signal: P0=${p0_hits}, P1=${p1_hits}, P2=${p2_hits}"
  if [ "$p0_hits" -gt 0 ]; then
    echo "- Action: trigger same-day P0 assessment and regression update."
  elif [ "$p1_hits" -gt 0 ]; then
    echo "- Action: include P1 items in weekly alignment."
  else
    echo "- Action: no immediate protocol-risk follow-up."
  fi
  echo
  echo "## Repositories"
  echo
} > "$summary_block"

awk -v f="$summary_block" '
  BEGIN {
    while ((getline line < f) > 0) s = s line "\n"
    close(f)
  }
  /## Summary/ { print; print ""; printf "%s", s; skip=1; next }
  skip==1 && /^## Repositories$/ { skip=0; next }
  skip==0 { print }
' "$tmp_dir/report.md" > "$OUT_FILE"

echo "Wrote upstream watch report: ${OUT_FILE}"
