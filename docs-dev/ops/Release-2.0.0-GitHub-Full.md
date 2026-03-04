# SKIntelligence 2.0.0 - Full Release Notes

发布日期：2026-03-04

## 版本定位

`2.0.0` 定位为 major release，原因是本次引入了新的模型提供方与运行时行为变化，同时包含若干需要下游确认的语义级修复。

## 变更范围

### 1) MLX Provider 与多模态能力

- 新增 `SKIMLXClient` 模块，接入 MLX 推理路径。
- CLI 支持 `--model-provider mlx` 及 `--mlx-*` 参数。
- 新增 VLM 图片输入支持：
  - `ChatRequestBody.Message.user(content: .parts([... .imageURL(...) ...]))`
  - 映射到 MLX `UserInput.Image`。
- 新增 MLX E2E 准备脚本与 runbook：
  - `scripts/mlx_e2e_prepare.sh`
  - `docs-dev/ops/MLX-E2E-Runbook.md`

### 2) 流式与工具调用语义修复

- 修复多工具流式调用 delta 索引：
  - 每个 tool-call 使用独立递增 index，避免 collector 错误合并。
- 修复多模态流式输入透传：
  - 最后一轮 user 的 images 会正确传入 `streamDetails(images:)`。
- 修复尾消息角色语义：
  - 仅当最后消息为 user 时抽离为 prompt；
  - `tool/assistant/system` 结尾保持在 history 中，不降级为普通 prompt 文本。

### 3) stop 序列语义修复

- stop sequence 现在保持原值（不 trim 空白和换行）。
- 支持并保留如 `"\n\n"`、`" END"`、`"END "` 这类边界 token 的字面意义。

### 4) ACP Serve 运行时优化

- `acp serve --model-provider mlx` 下改为复用单一 `MLXClient` 实例。
- 避免每个新建/fork 会话重复加载同一模型，降低延迟和内存压力。

### 5) 跨平台与质量收敛

- Linux 平台 transport 路径增加编译/运行降级分支（按能力启用）。
- Sendable 相关警告清理，面向 Swift 6 严格模式做前置收口。
- 构建/测试告警基线继续收敛。

## Breaking / Compatibility Notes

### 可能影响下游的行为变化

1. CLI 参数校验更严格  
- `--mlx-*` 参数在非 `--model-provider mlx` 下会报错。

2. stop 语义变化  
- 旧行为会 trim；新行为保持原样。
- 如果下游依赖“自动去空白”，需显式调整 stop 输入。

3. MLX 会话资源模型变化  
- serve 进程内复用 `MLXClient`，会话间共享已加载模型状态（符合预期优化）。

## 迁移建议（1.3.x -> 2.0.0）

1. CLI 调用方：
- 明确 provider：`--model-provider mlx`
- 仅在 MLX provider 下传 `--mlx-*`

2. stop 使用方：
- 传入所需的“精确边界 token”，不要依赖隐式 trim

3. 多模态使用方：
- 统一使用 `parts + imageURL`，并做一次 E2E 冒烟确认

4. ACP 服务部署方：
- 重新采样服务启动延迟与 steady-state 内存，确认复用收益与容量阈值

## 验证记录（发布前）

- 全量回归基线：
  - `swift test --package-path .`
  - `swift build -c release`
- 关键子集：
  - `swift test --filter MLXClientTests`
  - `swift test --filter SKICLIProcessTests`

## 风险与回滚

### 重点观察项（发布后 24h）

- MLX 模型首次加载与并发会话稳定性
- ACP websocket/stdio 路径在不同平台的行为一致性
- 依赖 stop 边界的业务 prompt 截断结果

### 回滚策略

1. 先在 Release 页面标注风险与临时规避方式。
2. 若需回退，按 hotfix 流程从 `2.0.0` 快速发布 `2.0.1`。
3. 阻塞级问题可临时建议下游回退到最新稳定 `1.3.x`。

## 相关文档

- `docs-dev/ops/Release-2.0.0.md`
- `docs-dev/ops/Release-2.0.0-GitHub-Short.md`
- `docs-dev/ops/MLX-E2E-Runbook.md`
