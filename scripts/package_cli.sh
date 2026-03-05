#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/package_cli.sh [--arch arm64|x86_64|all] [--output-dir <dir>] [--skip-build]

Examples:
  scripts/package_cli.sh
  scripts/package_cli.sh --arch arm64 --output-dir dist/cli
  scripts/package_cli.sh --skip-build --arch x86_64

Outputs:
  dist/cli/ski-macos-arm64.tar.gz
  dist/cli/ski-macos-arm64.sha256
  dist/cli/ski-macos-x86_64.tar.gz
  dist/cli/ski-macos-x86_64.sha256
EOF
}

find_binary_for_arch() {
  local arch="$1"
  local candidates=(
    ".build/${arch}-apple-macosx/release/ski"
    ".build/release/ski"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

build_and_package_arch() {
  local arch="$1"
  local output_dir="$2"
  local run_build="$3"
  local tar_name="ski-macos-${arch}.tar.gz"
  local tar_path="${output_dir}/${tar_name}"
  local sha_path="${output_dir}/ski-macos-${arch}.sha256"

  if [[ "${run_build}" == "1" ]]; then
    swift build -c release --product ski --arch "${arch}"
  fi

  local binary_path
  binary_path="$(find_binary_for_arch "${arch}")" || {
    echo "error: ski binary not found for arch=${arch}"
    exit 2
  }

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  cp "${binary_path}" "${tmp_dir}/ski"
  chmod 755 "${tmp_dir}/ski"

  tar -C "${tmp_dir}" -czf "${tar_path}" "ski"
  shasum -a 256 "${tar_path}" | sed "s#${tar_path}#${tar_name}#" > "${sha_path}"
  rm -rf "${tmp_dir}"

  echo "[package] arch=${arch} tar=${tar_path}"
}

main() {
  local arch="all"
  local output_dir="dist/cli"
  local run_build="1"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --arch)
        arch="${2:-}"
        shift 2
        ;;
      --output-dir)
        output_dir="${2:-}"
        shift 2
        ;;
      --skip-build)
        run_build="0"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "error: unknown argument: $1"
        usage
        exit 2
        ;;
    esac
  done

  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: scripts/package_cli.sh currently supports macOS only"
    exit 2
  fi

  mkdir -p "${output_dir}"

  case "${arch}" in
    arm64)
      build_and_package_arch "arm64" "${output_dir}" "${run_build}"
      ;;
    x86_64)
      build_and_package_arch "x86_64" "${output_dir}" "${run_build}"
      ;;
    all)
      build_and_package_arch "arm64" "${output_dir}" "${run_build}"
      build_and_package_arch "x86_64" "${output_dir}" "${run_build}"
      ;;
    *)
      echo "error: --arch must be one of arm64|x86_64|all"
      exit 2
      ;;
  esac

  echo "[package] done output_dir=${output_dir}"
}

main "$@"
