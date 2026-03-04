# Release 2.0.0

Date: 2026-03-04

## 1. Version Positioning

- Target tag: `2.0.0`
- Type: Major release
- Reason:
  - Introduces new MLX provider path and ACP runtime behavior expansion.
  - Includes API/behavior-level changes that require downstream validation and migration checks.

## 2. Scope

- New module and provider:
  - `SKIMLXClient` added as first-class model provider.
  - CLI supports `--model-provider mlx` and related MLX options.
- Multimodal/VLM support:
  - User image parts are mapped into MLX chat images.
  - VLM E2E path and runbook added.
- Streaming/tool-call correctness:
  - Multi-tool streaming delta index is now distinct and ordered.
  - Streaming input now preserves role semantics for non-user tail messages.
- Cross-platform and runtime hardening:
  - Linux compile fallback for transport paths.
  - WebSocket server capability guarded by platform availability.
- Stability/quality:
  - Sendable warnings cleanup for Swift 6 strict-mode readiness.
  - Build/test warning baseline reduced.

## 3. Breaking and Compatibility Notes

### 3.1 Potentially Breaking

- CLI runtime behavior now includes MLX provider selection and validation branch.
  - New validation errors appear when `--mlx-*` options are used outside `--model-provider mlx`.
- ACP serve path with MLX now reuses a shared MLX client instance.
  - Session startup/resource pattern differs from previous per-session re-init behavior.

### 3.2 Behavior Fixes (Important)

- Stop sequence semantics:
  - Stop strings are now preserved exactly (no trim of whitespace/newlines).
  - If downstream workflows relied on implicit trim behavior, update those assumptions.
- Streaming prompt construction:
  - Only tail `user` message is extracted as active prompt.
  - Tail `tool/assistant/system` messages stay in history to preserve role structure.

## 4. Migration Guide (1.3.x -> 2.0.0)

1. CLI integration:
   - If using MLX, switch to `--model-provider mlx`.
   - Keep `--mlx-*` options only with MLX provider.
2. Stop sequence usage:
   - Pass exact boundary tokens intentionally (e.g. `"\n\n"`, `" END"`).
   - Do not assume automatic trimming.
3. ACP multi-session expectations:
   - MLX model now loads once per serve process and is reused.
   - Review memory usage/latency baselines in long-running servers.
4. VLM/image workflows:
   - Use `user.content.parts` with `.imageURL(...)` for image input.
   - Verify E2E via `docs-dev/ops/MLX-E2E-Runbook.md`.

## 5. Validation Baseline

- Target validation before tagging:
  - `swift test --package-path .`
  - `swift build -c release`
- Key targeted validations completed during prep:
  - `swift test --filter MLXClientTests`
  - `swift test --filter SKICLIProcessTests`

## 6. Release Execution Checklist

1. Freeze:
   - Ensure no unresolved review comments in current PR/set.
2. Verify:
   - Run full regression and confirm no failures.
3. Docs:
   - Confirm release notes and runbooks are up to date.
4. Tag:
   - `git tag 2.0.0`
   - `git push origin 2.0.0`
5. Release:
   - Create GitHub Release for `2.0.0` with this note summary.
6. Post-release:
   - Broadcast migration highlights to downstream consumers.
   - Monitor first 24h for MLX runtime issues and ACP transport regressions.

## 7. Release-Day Commands (Copy/Paste)

```bash
# 0) 基线检查
swift test --package-path .
swift build -c release

# 1) 可选：关键子集复核
swift test --filter MLXClientTests
swift test --filter SKICLIProcessTests

# 2) 版本产物确认
git status --short
git tag --sort=-v:refname | head -n 5

# 3) 打 tag 并推送
git tag 2.0.0
git push origin 2.0.0

# 4) 创建 GitHub Release（如使用 gh）
gh release create 2.0.0 \
  --title "SKIntelligence 2.0.0" \
  --notes-file docs-dev/ops/Release-2.0.0.md
```

## 8. Rollback Plan

- If severe regression appears after tagging:
  1. Mark release as deprecated in release page notes.
  2. Prepare hotfix from `2.0.0` baseline (`2.0.1`) with minimal scoped fix.
  3. If blocking, advise temporary downgrade path to latest stable `1.3.x`.

## 9. Reference Documents

- `docs-dev/ops/MLX-E2E-Runbook.md`
- `docs-dev/dev/MLX-Standalone-Target-Design.md`
- `docs-dev/features/MLX-Standalone-Target-Spec.md`
- `docs-dev/ops/CI-AutoTag.md`
- `docs-dev/ops/Release-2.0.0-GitHub-Short.md`
- `docs-dev/ops/Release-2.0.0-GitHub-Full.md`
- `scripts/release_major.sh`
