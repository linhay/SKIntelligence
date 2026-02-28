#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# Fast, representative non-ACP smoke filters across core modules.
swift test \
  --filter SKIStreamingTests \
  --filter SKIMemoryTests \
  --filter SKIMCPIntegrationTests \
  --filter SKITextIndexTests
