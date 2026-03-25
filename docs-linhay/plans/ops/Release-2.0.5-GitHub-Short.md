# Release 2.0.5 (GitHub Short)

## Summary

- 文档系统完成迁移到 `docs-linhay/` 目录结构。
- MCP 文本提取增加兼容策略，适配上游 `.text` payload 结构变化。
- 发布脚本与巡检脚本已切换到新文档路径。

## Changes

1. 文档迁移
   - `memory/` -> `docs-linhay/memory/`
   - `docs-dev/dev` -> `docs-linhay/dev/`
   - `docs-dev/features` -> `docs-linhay/features/`
   - `docs-dev/ops` -> `docs-linhay/plans/ops/`
   - `references/` -> `docs-linhay/references/`
2. MCP 兼容性
   - `SKIMCPClient` 新增 `extractText` / `extractTextPayload`。
   - 支持直接 `String` 与 tuple-like payload（优先读取 `text` 字段）。
3. 工具链与门禁
   - 更新 `scripts/release_major.sh`、`scripts/acp_upstream_watch.sh` 路径默认值。
   - 更新文档边界检查脚本与路径引用测试。

## Validation

- 全量测试：`swift test --package-path .`
- 迁移相关回归：
  - `swift test --filter ACPSpecCoverageMatrixTests --filter ACPProtocolConformanceTests`
  - `swift test --filter SKIMCPClientTextExtractionTests`

## Upgrade Notes

1. 所有文档引用请使用 `docs-linhay/` 新路径。
2. 旧路径 `docs-dev/` 与 `memory/` 已迁移，不再作为主路径维护。
