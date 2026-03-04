#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

RUN_AFTER_PREPARE=0
MODEL_ID="${MLX_E2E_MODEL_ID:-}"
TIMEOUT_SECONDS="${MLX_E2E_REQUEST_TIMEOUT_SECONDS:-120}"
TEMPERATURE="${MLX_E2E_TEMPERATURE:-0}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run)
      RUN_AFTER_PREPARE=1
      shift
      ;;
    --model-id)
      MODEL_ID="${2:-}"
      shift 2
      ;;
    --timeout-seconds)
      TIMEOUT_SECONDS="${2:-120}"
      shift 2
      ;;
    --temperature)
      TEMPERATURE="${2:-0}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--run] [--model-id <id>] [--timeout-seconds <seconds>] [--temperature <value>]" >&2
      exit 2
      ;;
  esac
done

if [ ! -d ".build/checkouts/mlx-swift/xcode/MLX.xcodeproj" ]; then
  echo "Missing mlx-swift checkout. Run 'swift package resolve' first." >&2
  exit 1
fi

find_metallib() {
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*/MLX-*/Build/Products/Debug/Cmlx.framework/Versions/A/Resources/default.metallib" \
    -print 2>/dev/null | head -n1
}

METALLIB_SOURCE="$(find_metallib)"
if [ -z "$METALLIB_SOURCE" ]; then
  echo "[mlx-e2e] default.metallib not found, building Cmlx via xcodebuild..."
  xcodebuild build \
    -project .build/checkouts/mlx-swift/xcode/MLX.xcodeproj \
    -scheme Cmlx \
    -destination 'platform=macOS' \
    -configuration Debug >/tmp/mlx_e2e_xcodebuild.log 2>&1
  METALLIB_SOURCE="$(find_metallib)"
fi

if [ -z "$METALLIB_SOURCE" ] || [ ! -f "$METALLIB_SOURCE" ]; then
  echo "Failed to locate default.metallib after xcodebuild." >&2
  echo "Inspect /tmp/mlx_e2e_xcodebuild.log for details." >&2
  exit 1
fi

cp "$METALLIB_SOURCE" "$ROOT_DIR/default.metallib"
echo "[mlx-e2e] prepared $ROOT_DIR/default.metallib"

if [ "$RUN_AFTER_PREPARE" -eq 1 ]; then
  if [ -z "$MODEL_ID" ]; then
    echo "--run requires --model-id or MLX_E2E_MODEL_ID" >&2
    exit 2
  fi
  env \
    RUN_MLX_E2E_TESTS=1 \
    MLX_E2E_REQUEST_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
    MLX_E2E_TEMPERATURE="$TEMPERATURE" \
    MLX_E2E_MODEL_ID="$MODEL_ID" \
    swift test --filter MLXClientDeterminismE2ETests
else
  echo "[mlx-e2e] next:"
  if [ -z "$MODEL_ID" ]; then
    echo "  MLX_E2E_MODEL_ID='<your-model-id>' RUN_MLX_E2E_TESTS=1 MLX_E2E_REQUEST_TIMEOUT_SECONDS=$TIMEOUT_SECONDS MLX_E2E_TEMPERATURE=$TEMPERATURE swift test --filter MLXClientDeterminismE2ETests"
  else
    echo "  RUN_MLX_E2E_TESTS=1 MLX_E2E_REQUEST_TIMEOUT_SECONDS=$TIMEOUT_SECONDS MLX_E2E_TEMPERATURE=$TEMPERATURE MLX_E2E_MODEL_ID='$MODEL_ID' swift test --filter MLXClientDeterminismE2ETests"
  fi
fi
