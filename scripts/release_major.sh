#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/release_major.sh release <version> [notes_file]
  scripts/release_major.sh rollback <version>

Environment:
  DRY_RUN=1|0            default: 1 (safe mode; only prints commands)
  RUN_TESTS=1|0          default: 1
  RUN_BUILD=1|0          default: 1
  REMOTE=<name>          default: origin
  RELEASE_TITLE=<title>  default: SKIntelligence <version>

Examples:
  DRY_RUN=1 scripts/release_major.sh release 2.0.0 docs-dev/ops/Release-2.0.0-GitHub-Short.md
  DRY_RUN=0 scripts/release_major.sh release 2.0.0 docs-dev/ops/Release-2.0.0-GitHub-Full.md
  DRY_RUN=0 scripts/release_major.sh rollback 2.0.0
EOF
}

run() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    eval "$@"
  fi
}

require_clean_worktree() {
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: worktree is dirty, please commit/stash before release"
    exit 2
  fi
}

assert_tag_absent() {
  local version="$1"
  if git rev-parse -q --verify "refs/tags/${version}" >/dev/null; then
    echo "error: local tag ${version} already exists"
    exit 2
  fi
  if git ls-remote --tags "${REMOTE}" "refs/tags/${version}" | grep -q "${version}"; then
    echo "error: remote tag ${version} already exists on ${REMOTE}"
    exit 2
  fi
}

release_flow() {
  local version="$1"
  local notes_file="$2"
  local title="${RELEASE_TITLE:-SKIntelligence ${version}}"

  [[ -f "${notes_file}" ]] || {
    echo "error: notes file not found: ${notes_file}"
    exit 2
  }

  require_clean_worktree
  assert_tag_absent "${version}"

  if [[ "${RUN_TESTS}" == "1" ]]; then
    run "swift test --package-path ."
  fi
  if [[ "${RUN_BUILD}" == "1" ]]; then
    run "swift build -c release"
  fi

  run "git tag ${version}"
  run "git push ${REMOTE} ${version}"
  run "gh release create ${version} --title \"${title}\" --notes-file \"${notes_file}\""

  cat <<EOF
release flow finished for ${version}
if any post-release blocker is found, run:
  scripts/release_major.sh rollback ${version}
EOF
}

rollback_flow() {
  local version="$1"

  # Rollback branch:
  # 1) delete GitHub release
  # 2) delete remote tag
  # 3) delete local tag
  run "gh release delete ${version} --yes || true"
  run "git push ${REMOTE} :refs/tags/${version} || true"
  run "git tag -d ${version} || true"
  echo "rollback flow finished for ${version}"
}

main() {
  local mode="${1:-}"
  local version="${2:-}"
  local notes_file="${3:-docs-dev/ops/Release-${version}-GitHub-Short.md}"

  DRY_RUN="${DRY_RUN:-1}"
  RUN_TESTS="${RUN_TESTS:-1}"
  RUN_BUILD="${RUN_BUILD:-1}"
  REMOTE="${REMOTE:-origin}"

  if [[ -z "${mode}" || -z "${version}" ]]; then
    usage
    exit 2
  fi

  case "${mode}" in
    release) release_flow "${version}" "${notes_file}" ;;
    rollback) rollback_flow "${version}" ;;
    *) usage; exit 2 ;;
  esac
}

main "$@"
