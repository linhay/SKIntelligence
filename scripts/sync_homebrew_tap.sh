#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/sync_homebrew_tap.sh --tap-repo <owner/name> --formula <path> [--tap-formula-path <path>] [--ref <branch>] [--push 1|0]

Examples:
  scripts/sync_homebrew_tap.sh --tap-repo linhay/homebrew-tap --formula Formula/ski.rb --tap-formula-path Formula/ski.rb --push 1
  scripts/sync_homebrew_tap.sh --tap-repo linhay/homebrew-tap --formula dist/homebrew/ski.rb --tap-formula-path Formula/ski.rb --push 1
EOF
}

main() {
  local tap_repo=""
  local formula_path=""
  local tap_formula_path="Formula/ski.rb"
  local ref="main"
  local push_changes="1"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tap-repo)
        tap_repo="${2:-}"
        shift 2
        ;;
      --formula)
        formula_path="${2:-}"
        shift 2
        ;;
      --tap-formula-path)
        tap_formula_path="${2:-}"
        shift 2
        ;;
      --ref)
        ref="${2:-}"
        shift 2
        ;;
      --push)
        push_changes="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "error: unknown argument: $1" >&2
        usage
        exit 2
        ;;
    esac
  done

  [[ -n "${tap_repo}" ]] || { echo "error: --tap-repo is required" >&2; exit 2; }
  [[ -n "${formula_path}" ]] || { echo "error: --formula is required" >&2; exit 2; }
  [[ -n "${tap_formula_path}" ]] || { echo "error: --tap-formula-path is required" >&2; exit 2; }
  [[ -f "${formula_path}" ]] || { echo "error: formula file not found: ${formula_path}" >&2; exit 2; }

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "'"${tmp_dir}"'"' EXIT

  gh repo clone "${tap_repo}" "${tmp_dir}/tap"
  (
    cd "${tmp_dir}/tap"
    if git show-ref --verify --quiet "refs/heads/${ref}"; then
      git checkout "${ref}"
    elif git rev-parse --verify HEAD >/dev/null 2>&1; then
      git checkout -b "${ref}"
    else
      git checkout --orphan "${ref}"
    fi
  )

  mkdir -p "${tmp_dir}/tap/$(dirname "${tap_formula_path}")"
  cp "${formula_path}" "${tmp_dir}/tap/${tap_formula_path}"

  if [[ ! -f "${tmp_dir}/tap/README.md" ]]; then
    cat > "${tmp_dir}/tap/README.md" <<'EOF'
# homebrew-tap

Homebrew tap for SKIntelligence CLI.
EOF
  fi

  (
    cd "${tmp_dir}/tap"
    if [[ -z "$(git status --porcelain)" ]]; then
      echo "[tap] no changes to commit"
      exit 0
    fi
    git add "${tap_formula_path}" README.md
    git commit -m "chore(formula): update ski formula"
    if [[ "${push_changes}" == "1" ]]; then
      git push origin "${ref}"
      echo "[tap] pushed to ${tap_repo}@${ref}"
    else
      echo "[tap] push skipped (--push 0)"
    fi
  )
}

main "$@"
