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
  RUN_PACKAGE_CLI=1|0    default: 1
  RUN_HOMEBREW_FORMULA=1|0 default: 1
  EXPORT_FORMULA_TO_REPO=1|0 default: 0
  HOMEBREW_REPO=<owner/name> default: linhay/SKIntelligence
  HOMEBREW_TAP_REPO=<owner/name> default: linhay/homebrew-tap
  HOMEBREW_TAP_REF=<branch> default: main
  HOMEBREW_TAP_FORMULA_PATH=<path> default: Formula/ski.rb
  REMOTE=<name>          default: origin
  RELEASE_TITLE=<title>  default: SKIntelligence <version>

Examples:
  DRY_RUN=1 scripts/release_major.sh release 2.0.0 docs-linhay/plans/ops/Release-2.0.0-GitHub-Short.md
  DRY_RUN=0 scripts/release_major.sh release 2.0.0 docs-linhay/plans/ops/Release-2.0.0-GitHub-Full.md
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
  local release_skill_asset_path="skills/dist/skintelligence.skill"
  local release_cli_asset_dir="dist/cli"
  local release_homebrew_dir="dist/homebrew"
  local asset_args=""
  local cli_asset_count=0

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

  if [[ "${RUN_PACKAGE_CLI}" == "1" ]]; then
    run "scripts/package_cli.sh --arch all --output-dir ${release_cli_asset_dir}"
  fi

  if [[ "${RUN_HOMEBREW_FORMULA}" == "1" ]]; then
    run "scripts/generate_homebrew_formula.sh --version ${version} --repo ${HOMEBREW_REPO} --sha-dir ${release_cli_asset_dir} --output ${release_homebrew_dir}/ski.rb"
  fi

  if [[ -f "${release_skill_asset_path}" ]]; then
    asset_args="\"${release_skill_asset_path}#skintelligence.skill\""
  fi

  for release_asset_path in \
    "${release_cli_asset_dir}"/ski-macos-*.tar.gz \
    "${release_cli_asset_dir}"/ski-macos-*.sha256; do
    if [[ -f "${release_asset_path}" ]]; then
      asset_args+=" \"${release_asset_path}#$(basename "${release_asset_path}")\""
      cli_asset_count=$((cli_asset_count + 1))
    fi
  done

  if [[ "${RUN_PACKAGE_CLI}" == "1" && "${cli_asset_count}" -eq 0 ]]; then
    echo "error: no cli assets found under ${release_cli_asset_dir}"
    exit 2
  fi

  if [[ "${RUN_HOMEBREW_FORMULA}" == "1" ]]; then
    local formula_asset="${release_homebrew_dir}/ski.rb"
    if [[ ! -f "${formula_asset}" ]]; then
      echo "error: homebrew formula not found: ${formula_asset}"
      exit 2
    fi
    asset_args+=" \"${formula_asset}#ski.rb\""
    if [[ "${EXPORT_FORMULA_TO_REPO}" == "1" ]]; then
      run "scripts/sync_homebrew_tap.sh --tap-repo ${HOMEBREW_TAP_REPO} --formula ${formula_asset} --tap-formula-path ${HOMEBREW_TAP_FORMULA_PATH} --ref ${HOMEBREW_TAP_REF} --push 1"
    fi
  fi

  run "git tag ${version}"
  run "git push ${REMOTE} ${version}"
  run "gh release create ${version} --title \"${title}\" --notes-file \"${notes_file}\" ${asset_args}"

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
  local notes_file="${3:-docs-linhay/plans/ops/Release-${version}-GitHub-Short.md}"

  DRY_RUN="${DRY_RUN:-1}"
  RUN_TESTS="${RUN_TESTS:-1}"
  RUN_BUILD="${RUN_BUILD:-1}"
  RUN_PACKAGE_CLI="${RUN_PACKAGE_CLI:-1}"
  RUN_HOMEBREW_FORMULA="${RUN_HOMEBREW_FORMULA:-1}"
  EXPORT_FORMULA_TO_REPO="${EXPORT_FORMULA_TO_REPO:-0}"
  HOMEBREW_REPO="${HOMEBREW_REPO:-linhay/SKIntelligence}"
  HOMEBREW_TAP_REPO="${HOMEBREW_TAP_REPO:-linhay/homebrew-tap}"
  HOMEBREW_TAP_REF="${HOMEBREW_TAP_REF:-main}"
  HOMEBREW_TAP_FORMULA_PATH="${HOMEBREW_TAP_FORMULA_PATH:-Formula/ski.rb}"
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
