# MLX Standalone Target 接入规格

## 背景

当前仓库主要通过 OpenAI-compatible 接口对接远端模型。为支持本地推理能力，需要接入 `mlx-swift-lm`，并避免影响现有主链路与非 Apple 平台构建。

## 目标

1. 新增独立 target：`SKIMLXClient`，实现 `SKILanguageModelClient`。
2. 保持 `SKIntelligence` 与 `SKIClients` 既有 API 兼容，不引入强耦合。
3. 支持非流式、流式、工具调用的最小可用闭环。
4. 输出可观测指标：模型加载耗时、推理吞吐与取消状态。

## 非目标

1. 不改造 `SKILanguageModelSession` 的主流程协议。
2. 不实现 VLM（图像/视频）能力。
3. 不在本期重构全局 provider 配置系统。

## API 设计

1. 新增 product：`SKIMLXClient`。
2. 新增类型：
   - `MLXClient: SKILanguageModelClient`
   - `MLXClient.Configuration`
   - `MLXClientError`
3. `MLXClient.Configuration` 最小字段：
   - `modelID`
   - `revision`
   - `toolCallEnabled`
   - `requestTimeout`
   - `defaultSeed`
   - `defaultStop`
4. `MLXClient` 公开只读状态：
   - `isModelLoaded`
5. 可选本地观测事件（非协议域）：
   - `MLXClientTelemetryEvent`
   - `MLXClient.Configuration.telemetrySink`

## 行为规则

1. target 隔离：MLX 代码仅存在于 `SKIMLXClient`，默认调用方按需引入。
2. 输入映射：
   - `ChatRequestBody.messages` 转 MLX chat 历史；
   - `tools` 转 MLX 工具描述；
   - `stop` 在客户端层做文本截断（非流式与流式）；
   - `seed` 通过 MLX 随机状态注入；
   - 未支持字段忽略且不导致崩溃。
3. 输出映射：
   - 文本输出映射到 `ChatResponseBody` / `SKIResponseChunk.text`；
   - 工具调用映射到 `tool_calls` / `toolCallDeltas`；
   - usage 缺失字段允许为 `nil`。
4. 取消语义：
   - `Task.cancel()` 必须可中断流式与非流式请求。
5. 可观测性：
   - 至少覆盖：模型加载耗时、请求总耗时、流式首 chunk 延迟、超时/取消状态。
6. 对暂未支持的请求字段：
   - 不得伪支持；
   - 必须通过本地 telemetry 明确暴露“已忽略”事实，便于接入方排障。
7. `stop`：
   - 非流式与流式都应按 stop 序列提前截断输出；
   - 流式需覆盖跨 chunk 边界的 stop 匹配。

## BDD 验收场景

1. Given 调用方仅依赖 `SKIntelligence` 与 `SKIClients`
   - When 构建项目
   - Then 构建不因 MLX 依赖失败。

2. Given 初始化 `MLXClient` 且后端返回普通文本
   - When 调用 `respond`
   - Then 返回 `assistant` 文本，`finish_reason=stop`。

3. Given 初始化 `MLXClient` 且后端返回工具调用
   - When 调用 `respond`
   - Then `ChatResponseBody.message.toolCalls` 可被 `SKILanguageModelSession` 消费。

4. Given 初始化 `MLXClient` 且后端返回流式文本
   - When 调用 `streamingRespond`
   - Then 消费端可按 chunk 增量读取文本。

5. Given 初始化 `MLXClient` 且后端返回流式工具调用
   - When 调用 `streamingRespond`
   - Then 输出 `toolCallDeltas`，可被 `ToolCallCollector` 聚合。

6. Given 流式请求处理中
   - When 上层触发取消
   - Then 流应尽快结束并抛出取消错误。

## 验收标准

1. 新增 `SKIMLXClientTests` 覆盖上述场景并通过。
2. 现有 `SKIntelligenceTests` 核心流式与会话测试不回归。
3. 新增文档与实现保持一致，可直接复现最小接入路径。
4. `ski acp serve` 可通过 `--model-provider mlx` 启用 MLX 客户端，并支持 `--mlx-*` 参数。
5. `--mlx-seed/--mlx-stop` 作为会话默认采样参数，且请求显式参数优先于默认值。
6. 可选 E2E（`MLXClientDeterminismE2ETests`）在运行环境缺少 `*.metallib` 时必须 `skip` 而非崩溃，并给出明确跳过原因。
7. 提供可执行的本机准备脚本（`scripts/mlx_e2e_prepare.sh`），用于生成/放置 `default.metallib` 并给出 E2E 运行命令。
