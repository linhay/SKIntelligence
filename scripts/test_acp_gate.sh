#!/usr/bin/env bash
set -euo pipefail

swift test \
  --filter ACP \
  --filter SKICLITests \
  --filter SKICLIProcessTests \
  --filter JSONRPCCodecTests
