# SKIntelligence Troubleshooting

## 1. `session/new` timeout or parse failure

Signal:
- Upstream parse errors or timeout during early ACP handshake.

Actions:
1. Run `swift test --filter JSONRPCCodecTests`.
2. Verify JSON-RPC payload compatibility expectations.
3. Re-run minimal connect command.

## 2. codex-acp command unavailable

Signal:
- `npx` cannot resolve `@zed-industries/codex-acp`.

Actions:
1. Run `npx -y @zed-industries/codex-acp --help`.
2. Check network/npm availability.
3. Continue with local ACP regression if external dependency is blocked.

## 3. Permission allow/deny has no visible difference

Signal:
- Both branches produce similar final result.

Actions:
1. Inspect permission request count in client logs.
2. Treat as scenario not hitting permission callback path.
3. Build a prompt that forces permission path if strict validation is required.

## 4. Stdio session reuse fails across runs

Signal:
- Reusing old `sessionId` after a new stdio process returns not found.

Actions:
1. Use multi-prompt single connection for continuity.
2. For cross-connection reuse, use ws server lifecycle instead.

## 5. qmd update does not index current repo

Signal:
- `qmd update` reports a different collection root.

Actions:
1. Capture mismatch in memory risk note.
2. Update qmd collection config to current repository.
3. Re-run `qmd update && qmd embed`.

## 6. MLX E2E fails with `Failed to load the default metallib`

Signal:
- E2E process exits with MLX runtime error about `default.metallib`.

Actions:
1. Run `scripts/mlx_e2e_prepare.sh --model-id <model-id>`.
2. Confirm `default.metallib` exists at repo root.
3. Re-run E2E with `--temperature 0`.

## 7. MLX E2E is skipped due to missing `*.metallib`

Signal:
- `MLXClientDeterminismE2ETests` reports no metal library found in runtime search paths.

Actions:
1. Run `scripts/mlx_e2e_prepare.sh --model-id <model-id>`.
2. Optionally set `MLX_E2E_METALLIB_DIR=<dir>` if metallib is stored outside repo root.
3. Re-run:
   `RUN_MLX_E2E_TESTS=1 MLX_E2E_MODEL_ID='<id>' swift test --filter MLXClientDeterminismE2ETests`

## 8. MLX E2E determinism assertion fails with same seed

Signal:
- Two outputs differ under same prompt and seed.

Actions:
1. Set `MLX_E2E_TEMPERATURE=0`.
2. Pin `MLX_E2E_MODEL_REVISION` and keep prompt unchanged.
3. Increase `MLX_E2E_REQUEST_TIMEOUT_SECONDS` if generation is unstable due to timeout pressure.
