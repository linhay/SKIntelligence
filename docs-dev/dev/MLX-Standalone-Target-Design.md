# MLX Standalone Target 设计说明

关联需求：`docs-dev/features/MLX-Standalone-Target-Spec.md`

## 1. 设计目标

1. 通过独立 target `SKIMLXClient` 接入 MLX，不影响主链路。
2. 复用 `SKILanguageModelClient` 协议，保持会话层 `SKILanguageModelSession` 无需改造。
3. 提供可测试后端抽象，确保本地推理逻辑可用 mock 覆盖。

## 2. 模块与依赖

1. 新增 product：`SKIMLXClient`
2. target 依赖：
   - `SKIntelligence`
   - `MLXLMCommon`（来自 `mlx-swift-lm`）
   - `MLXLLM`（来自 `mlx-swift-lm`，确保模型工厂注册代码可链接）
   - `MLXVLM`（来自 `mlx-swift-lm`，确保 VLM 工厂与 `qwen2_vl/qwen2_5_vl` 类型可注册）
   - `MLX`（来自 `mlx-swift`，用于随机状态与底层推理运行时）
3. 测试 target：`SKIMLXClientTests`

## 3. 核心实现

### 3.1 MLXClient

1. 类型：`actor MLXClient: SKILanguageModelClient`
2. 对外能力：
   - `respond(_:)`：非流式，输出 `SKIResponse<ChatResponseBody>`
   - `streamingRespond(_:)`：流式，输出 `SKIResponseStream`
3. 配置：
   - `modelID`
   - `revision`
   - `toolCallEnabled`
   - `requestTimeout`

### 3.2 Backend 抽象

1. 协议：`MLXClientBackend`
2. 生产实现：`DefaultMLXBackend`
3. 测试实现：`MockBackend`

该抽象将模型加载/推理与 `MLXClient` 的协议映射解耦，使测试无需真实模型下载。

### 3.3 输入输出映射

1. 输入：
   - `ChatRequestBody.messages` -> `MLXLMCommon.Chat.Message`
   - `user.content.parts` 中 `image_url` -> `UserInput.Image.url`（透传到 MLX VLM）
   - `ChatRequestBody.tools` -> `ToolSpec` 结构（通过 JSON 编解码桥接）
2. 输出：
   - 文本 -> `ChoiceMessage.content`
   - 工具调用 -> `tool_calls`
   - usage -> `ChatUsage`（可映射字段）
3. 流式：
   - `Generation.chunk` -> `SKIResponseChunk.text`
   - `Generation.toolCall` -> `toolCallDeltas`
   - `Generation.info` -> `usage`

## 4. 并发与取消

1. `MLXClient` 为 actor，保证状态与后端调用串行化。
2. 流式使用 `AsyncThrowingStream`，通过 `onTermination` 取消 producer task，确保取消可及时传递。

## 5. 已知限制

1. 当前已支持图片 URL 输入（VLM），但仅映射 `user.content.parts` 中的 `image_url`。
2. 远程图片 URL 建议由上层先下载到本地后再传 `file://`，避免底层图片加载无超时导致阻塞。
3. 对未映射的请求字段采用忽略策略，不保证 provider 完全语义一致。

## 6. 本次补充接入（2026-03-03）

1. `ChatRequestBody` -> MLX 生成参数映射：
   - `maxCompletionTokens` -> `GenerateParameters.maxTokens`
   - `temperature` -> `GenerateParameters.temperature`（最小值 0）
   - `topP` -> `GenerateParameters.topP`（裁剪到 0...1）
2. `MLXClient.Configuration.requestTimeout` 已生效：
   - 非流式与流式建链阶段均使用超时保护；
   - 超时抛出 `MLXClientError.requestTimedOut(seconds:)`。
   - 流式读取阶段按 chunk 等待也受超时保护（无增量输出时可超时退出）。
3. CLI 服务端新增 provider 接线：
   - `ski acp serve --model-provider echo|mlx`
   - MLX 相关参数：
     - `--mlx-model-id`
     - `--mlx-revision`
     - `--mlx-disable-tool-call`
     - `--mlx-request-timeout-ms`
     - `--mlx-seed`
     - `--mlx-stop`（可重复）
4. 新增本地 telemetry（非 ACP 协议域）：
   - `MLXClientTelemetryEvent.modelLoaded`
   - `MLXClientTelemetryEvent.respondFinished`
   - `MLXClientTelemetryEvent.streamFinished`
   - `MLXClientTelemetryEvent.requestOptionsIgnored`（当前用于 `seed` 显式降级提示）
   - 通过 `MLXClient.Configuration.telemetrySink` 注入，不改变协议载荷。
5. 参数映射细化：
   - `frequencyPenalty/presencePenalty` 映射为 `GenerateParameters.repetitionPenalty`（仅正值，范围收敛到 1...2）；
   - 负值 penalty 不映射，避免与 MLX 语义错配。
   - `stop` 通过客户端文本截断支持（非流式与流式，含跨 chunk 边界）。
   - `seed` 通过 `withRandomState(RandomState(seed: ...))` 注入到生成任务。
   - `MLXClient.Configuration.defaultSeed/defaultStop` 作为请求默认值；
     若请求显式携带 `seed/stop`，以请求值优先覆盖默认值。
   - 未支持字段通过 telemetry 上报 `requestOptionsIgnored.names`，当前覆盖：
     - `model`
     - `logit_bias`
     - `logprobs`
     - `n`
     - `parallel_tool_calls`
     - `response_format`
     - `store`
     - `stream`
     - `stream_options`
     - `tool_choice`
     - `top_logprobs`
     - `user`
6. 真实模型可复现性验证（可选 E2E）：
   - 新增 `MLXClientDeterminismE2ETests`，默认跳过；
   - 启用条件：
     - `RUN_MLX_E2E_TESTS=1`
     - `MLX_E2E_MODEL_ID=<model>`
   - 可选参数：
     - `MLX_E2E_MODEL_REVISION`（默认 `main`）
     - `MLX_E2E_PROMPT`（默认内置短句）
     - `MLX_E2E_REQUEST_TIMEOUT_SECONDS`（默认 `180`）
     - `MLX_E2E_TEMPERATURE`（默认 `0`，优先保证 deterministic）
     - `MLX_E2E_METALLIB_DIR`（可显式指定 metallib 目录）
   - 运行前置检查：
     - 若运行目录、`.build`、`DYLD_FRAMEWORK_PATH`、`MLX_E2E_METALLIB_DIR` 中均未发现 `*.metallib`，测试直接 `XCTSkip`；
     - 目的：避免在未准备好 MLX Metal 运行时时触发底层崩溃。
   - 本地一键准备脚本：
     - `scripts/mlx_e2e_prepare.sh`
     - 行为：
       1. 若缺少 `default.metallib`，调用 `xcodebuild` 构建 `mlx-swift` 的 `Cmlx`；
       2. 将 `default.metallib` 复制到仓库根目录；
       3. 输出或直接执行 E2E 命令。
     - 示例：
       - 仅准备：`scripts/mlx_e2e_prepare.sh --model-id mlx-community/Qwen2.5-0.5B-4bit`
       - 准备并执行：`scripts/mlx_e2e_prepare.sh --run --model-id mlx-community/Qwen2.5-0.5B-4bit`

## 7. 测试矩阵（当前状态）

1. 参数映射：
   - `maxCompletionTokens/temperature/topP` 映射测试已覆盖。
   - `frequencyPenalty/presencePenalty -> repetitionPenalty` 的正值、负值、上界行为已覆盖。
2. 默认值与覆盖优先级：
   - `defaultSeed/defaultStop` 生效已覆盖；
   - 请求显式 `seed/stop` 覆盖默认值已覆盖。
3. `stop` 行为：
   - 非流式截断已覆盖；
   - 流式跨 chunk 边界截断已覆盖。
4. 超时与取消：
   - 非流式超时已覆盖；
   - 流式建链/读取阶段超时已覆盖；
   - 流式取消传播已覆盖。
5. telemetry：
   - `modelLoaded/respondFinished/streamFinished` 已覆盖；
   - `requestOptionsIgnored`：
     - `respond` 路径已覆盖（`requestKind=respond`）；
     - `streamingRespond` 路径已覆盖（`requestKind=stream`）。
6. CLI 参数校验：
   - `--model-provider` 与 `--mlx-*` 作用域约束已覆盖；
   - `--mlx-request-timeout-ms` 在 `mlx` provider 下的取值校验已覆盖；
   - 作用域错误优先于取值错误的顺序语义已覆盖。
