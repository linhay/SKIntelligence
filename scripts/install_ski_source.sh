#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Install ski by building from source (no GitHub release required).

Usage:
  scripts/install_ski_source.sh [--source-dir <path>] [--repo <owner/name>] [--ref <git-ref>] [--prefix <path>] [--config debug|release]

Examples:
  scripts/install_ski_source.sh
  scripts/install_ski_source.sh --source-dir "$PWD" --prefix "$HOME/.local" --config debug
  scripts/install_ski_source.sh --repo linhay/SKIntelligence --ref main --prefix "$HOME/.local"
EOF
}

SOURCE_DIR=""
REPO="linhay/SKIntelligence"
REF="main"
PREFIX="${HOME}/.local"
CONFIG="release"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir)
      [[ $# -ge 2 && "${2:-}" != -* ]] || { echo "error: --source-dir requires a value" >&2; exit 2; }
      SOURCE_DIR="${2:-}"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 && "${2:-}" != -* ]] || { echo "error: --repo requires a value" >&2; exit 2; }
      REPO="${2:-}"
      shift 2
      ;;
    --ref)
      [[ $# -ge 2 && "${2:-}" != -* ]] || { echo "error: --ref requires a value" >&2; exit 2; }
      REF="${2:-}"
      shift 2
      ;;
    --prefix)
      [[ $# -ge 2 && "${2:-}" != -* ]] || { echo "error: --prefix requires a value" >&2; exit 2; }
      PREFIX="${2:-}"
      shift 2
      ;;
    --config)
      [[ $# -ge 2 && "${2:-}" != -* ]] || { echo "error: --config requires a value" >&2; exit 2; }
      CONFIG="${2:-}"
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
  echo "error: scripts/install_ski_source.sh currently supports macOS only" >&2
  exit 2
fi

if [[ "${CONFIG}" != "debug" && "${CONFIG}" != "release" ]]; then
  echo "error: --config must be 'debug' or 'release'" >&2
  exit 2
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "error: swift toolchain not found in PATH" >&2
  exit 2
fi

if ! command -v git >/dev/null 2>&1; then
  echo "error: git not found in PATH" >&2
  exit 2
fi

TEMP_DIR=""
if [[ -z "${SOURCE_DIR}" ]]; then
  TEMP_DIR="$(mktemp -d)"
  trap '[[ -n "${TEMP_DIR}" ]] && rm -rf "${TEMP_DIR}"' EXIT
  SOURCE_DIR="${TEMP_DIR}/src"
  git clone --depth 1 --branch "${REF}" "https://github.com/${REPO}.git" "${SOURCE_DIR}"
fi

[[ -d "${SOURCE_DIR}" ]] || {
  echo "error: source directory not found: ${SOURCE_DIR}" >&2
  exit 2
}

pushd "${SOURCE_DIR}" >/dev/null
swift build -c "${CONFIG}" --product ski
BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)"
SKI_BIN="${BIN_PATH}/ski"

if [[ ! -x "${SKI_BIN}" ]]; then
  echo "error: built ski binary not found at ${SKI_BIN}" >&2
  exit 2
fi

BIN_DIR="${PREFIX}/bin"
mkdir -p "${BIN_DIR}"
install -m 0755 "${SKI_BIN}" "${BIN_DIR}/ski"

SOURCE_VERSION="$(git -C "${SOURCE_DIR}" describe --tags --always --dirty 2>/dev/null || true)"
SOURCE_VERSION="${SOURCE_VERSION#v}"
if [[ -n "${SOURCE_VERSION}" ]]; then
  printf '%s\n' "${SOURCE_VERSION}" > "${BIN_DIR}/ski.version"
fi
popd >/dev/null

echo "installed: ${BIN_DIR}/ski"
"${BIN_DIR}/ski" --version || true

if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
  cat <<EOF
note: ${BIN_DIR} is not in PATH.
add this line to your shell profile:
  export PATH="${BIN_DIR}:\$PATH"
EOF
fi
