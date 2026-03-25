# SKIntelligence Command Patterns

## Focused Tests

```bash
swift test --filter ACPProtocolConformanceTests
swift test --filter ACPAgentServiceTests
swift test --filter SKICLIProcessTests
swift test --filter SKICLITests
```

Combine filters when needed:

```bash
swift test --filter ACP --filter SKICLITests
```

## ACP Regression Suite

Default:

```bash
./scripts/acp_regression_suite.sh
```

With codex probes:

```bash
RUN_CODEX_PROBES=1 ./scripts/acp_regression_suite.sh
```

Strict codex probe mode:

```bash
RUN_CODEX_PROBES=1 STRICT_CODEX_PROBES=1 ./scripts/acp_regression_suite.sh
```

Summary output:

```bash
ACP_SUITE_SUMMARY_JSON=.local/acp-summary-latest.json ./scripts/acp_regression_suite.sh
jq '{schemaVersion, ciRecommendation, requiredPassed, alerts}' .local/acp-summary-latest.json
```

## codex-acp Stdio Connect

```bash
swift run ski acp client connect \
  --transport stdio \
  --cmd npx \
  --args=-y \
  --args=@zed-industries/codex-acp \
  --cwd "$PWD" \
  --prompt "hello" \
  --json
```

## Session Stop Examples

```bash
swift run ski acp client stop-ws --endpoint ws://127.0.0.1:8900 --session-id sess_123 --json
swift run ski acp client stop-stdio --cmd npx --args=-y --args=@zed-industries/codex-acp --session-id sess_123 --json
```

## MLX Real-Model E2E

Prepare only:

```bash
scripts/mlx_e2e_prepare.sh --model-id mlx-community/Qwen2.5-0.5B-4bit
```

Prepare and run determinism check:

```bash
scripts/mlx_e2e_prepare.sh --run --model-id mlx-community/Qwen2.5-0.5B-4bit --timeout-seconds 120 --temperature 0
```

Manual run (after prepare):

```bash
RUN_MLX_E2E_TESTS=1 \
MLX_E2E_MODEL_ID='mlx-community/Qwen2.5-0.5B-4bit' \
MLX_E2E_REQUEST_TIMEOUT_SECONDS=120 \
MLX_E2E_TEMPERATURE=0 \
swift test --filter MLXClientDeterminismE2ETests
```
