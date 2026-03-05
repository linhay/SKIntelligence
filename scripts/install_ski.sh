#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/install_ski.sh [--version <tag>] [--arch arm64|x86_64] [--prefix <path>] [--repo <owner/name>]

Examples:
  scripts/install_ski.sh
  scripts/install_ski.sh --version 2.0.0
  scripts/install_ski.sh --prefix "$HOME/.local"

Notes:
  - macOS only.
  - Default version is resolved from GitHub releases/latest API.
EOF
}

resolve_default_arch() {
  local machine_arch
  machine_arch="$(uname -m)"
  case "${machine_arch}" in
    arm64|aarch64) echo "arm64" ;;
    x86_64) echo "x86_64" ;;
    *)
      echo "error: unsupported architecture: ${machine_arch}" >&2
      exit 2
      ;;
  esac
}

resolve_latest_version() {
  local repo="$1"
  local latest_url="https://api.github.com/repos/${repo}/releases/latest"
  local version
  version="$(curl -fsSL "${latest_url}" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  if [[ -z "${version}" ]]; then
    echo "error: failed to resolve latest release tag from ${latest_url}" >&2
    exit 2
  fi
  printf '%s\n' "${version}"
}

main() {
  local repo="linhay/SKIntelligence"
  local version=""
  local arch=""
  local prefix=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        repo="${2:-}"
        shift 2
        ;;
      --version)
        version="${2:-}"
        shift 2
        ;;
      --arch)
        arch="${2:-}"
        shift 2
        ;;
      --prefix)
        prefix="${2:-}"
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

  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: scripts/install_ski.sh currently supports macOS only" >&2
    exit 2
  fi

  if [[ -z "${arch}" ]]; then
    arch="$(resolve_default_arch)"
  fi
  case "${arch}" in
    arm64|x86_64) ;;
    *)
      echo "error: --arch must be arm64 or x86_64" >&2
      exit 2
      ;;
  esac

  if [[ -z "${version}" ]]; then
    version="$(resolve_latest_version "${repo}")"
  fi

  if [[ -z "${prefix}" ]]; then
    if [[ "${arch}" == "arm64" ]]; then
      prefix="/opt/homebrew"
    else
      prefix="/usr/local"
    fi
  fi

  local asset_name="ski-macos-${arch}.tar.gz"
  local base_url="https://github.com/${repo}/releases/download/${version}"
  local asset_url="${base_url}/${asset_name}"
  local checksum_url="${asset_url}.sha256"

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' EXIT

  echo "[install] repo=${repo} version=${version} arch=${arch}"
  echo "[install] downloading ${asset_url}"
  curl -fsSL "${asset_url}" -o "${tmp_dir}/${asset_name}"

  if curl -fsSL "${checksum_url}" -o "${tmp_dir}/${asset_name}.sha256"; then
    (
      cd "${tmp_dir}"
      shasum -a 256 -c "${asset_name}.sha256"
    )
  else
    echo "[install] checksum missing, skip verification: ${checksum_url}"
  fi

  tar -C "${tmp_dir}" -xzf "${tmp_dir}/${asset_name}"
  [[ -f "${tmp_dir}/ski" ]] || {
    echo "error: archive does not contain ski binary" >&2
    exit 2
  }

  local bin_dir="${prefix}/bin"
  mkdir -p "${bin_dir}"
  install -m 0755 "${tmp_dir}/ski" "${bin_dir}/ski"

  echo "[install] installed: ${bin_dir}/ski"
  if [[ ":$PATH:" != *":${bin_dir}:"* ]]; then
    echo "[install] warning: ${bin_dir} is not in PATH"
  fi
  "${bin_dir}/ski" --help >/dev/null
  echo "[install] ski is ready"
}

main "$@"
