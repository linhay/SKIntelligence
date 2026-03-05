#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/generate_homebrew_formula.sh --version <version> [--repo <owner/name>] [--sha-dir <dir>] [--output <path>]

Examples:
  scripts/generate_homebrew_formula.sh --version 2.0.0
  scripts/generate_homebrew_formula.sh --version 2.0.0 --sha-dir dist/cli --output dist/homebrew/ski.rb

Required files in --sha-dir:
  ski-macos-arm64.sha256
  ski-macos-x86_64.sha256
EOF
}

read_sha() {
  local file="$1"
  [[ -f "${file}" ]] || {
    echo "error: missing checksum file: ${file}" >&2
    exit 2
  }
  awk '{print $1}' "${file}"
}

main() {
  local version=""
  local repo="linhay/SKIntelligence"
  local sha_dir="dist/cli"
  local output="dist/homebrew/ski.rb"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        version="${2:-}"
        shift 2
        ;;
      --repo)
        repo="${2:-}"
        shift 2
        ;;
      --sha-dir)
        sha_dir="${2:-}"
        shift 2
        ;;
      --output)
        output="${2:-}"
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

  if [[ -z "${version}" ]]; then
    echo "error: --version is required" >&2
    usage
    exit 2
  fi

  local arm_sha
  local intel_sha
  arm_sha="$(read_sha "${sha_dir}/ski-macos-arm64.sha256")"
  intel_sha="$(read_sha "${sha_dir}/ski-macos-x86_64.sha256")"

  local base_url="https://github.com/${repo}/releases/download/${version}"
  mkdir -p "$(dirname "${output}")"

  cat > "${output}" <<EOF
class Ski < Formula
  desc "SKIntelligence CLI"
  homepage "https://github.com/${repo}"
  version "${version}"
  license "MIT"

  on_macos do
    on_arm do
      url "${base_url}/ski-macos-arm64.tar.gz"
      sha256 "${arm_sha}"
    end
    on_intel do
      url "${base_url}/ski-macos-x86_64.tar.gz"
      sha256 "${intel_sha}"
    end
  end

  def install
    bin.install "ski"
  end

  test do
    assert_match "SKIntelligence CLI", shell_output("#{bin}/ski --help")
  end
end
EOF

  echo "[homebrew] formula generated: ${output}"
}

main "$@"
