# SKIntelligence 2.0.0

发布日期：2026-03-04

## TL;DR

`2.0.0` 是一次大版本升级，核心新增 MLX provider（含 VLM 多模态输入能力）并强化 ACP/CLI 跨平台与流式行为正确性。  
同时修复了多个关键语义问题（tool-call 流式索引、stop 序列精确保留、非 user 尾消息角色保持）。

## 主要变化

- 新增 `SKIMLXClient` 作为一等模型提供方。
- `ski acp serve` 支持 `--model-provider mlx` 与 MLX 参数族。
- VLM 图片输入链路可用：`user.content.parts.imageURL` -> MLX images。
- 多工具流式调用索引修复，避免 tool-call 合并错乱。
- 流式输入构造修复，保留 non-user 尾消息角色语义。
- stop 序列不再 trim，严格按调用方字面值生效。
- ACP 多会话下复用同一 `MLXClient`，避免重复加载模型。
- Linux 兼容与降级路径完善（含 transport 平台分支）。

## 兼容性与迁移提示

- 使用 MLX 时请显式传 `--model-provider mlx`，`--mlx-*` 仅在该模式下有效。
- 依赖 stop 自动裁剪空白的调用方需要调整（现在不再自动 trim）。
- 需要图片理解时请确保输入走 `parts + imageURL` 路径。

## 验证

- `swift test --package-path .`
- `swift build -c release`
- 关键子集：
  - `swift test --filter MLXClientTests`
  - `swift test --filter SKICLIProcessTests`

## 文档

- 发布主文档：`docs-linhay/plans/ops/Release-2.0.0.md`
- 完整版发布说明：`docs-linhay/plans/ops/Release-2.0.0-GitHub-Full.md`
