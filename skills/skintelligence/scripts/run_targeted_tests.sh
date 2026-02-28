#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <test-filter...>" >&2
  exit 2
fi

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

CMD=(swift test)
for filter in "$@"; do
  CMD+=(--filter "$filter")
done

"${CMD[@]}"
