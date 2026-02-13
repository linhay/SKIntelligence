# SKIntelligence CLI 技术方案（v0）

关联需求：`docs-dev/features/CLI-Benchmark-Spec.md`
ACP WebSocket 规格：`docs-dev/features/ACP-WebSocket-Serve-Spec.md`

## 1. 设计原则
- 子命令清晰分层：`chat/run/config/version`。
- 输出稳定：人类可读默认，脚本优先用 `--json`。
- 错误可诊断：统一错误类型与退出码映射。

## 2. 模块划分
- `CLIEntry`：参数解析与命令路由。
- `ApplicationContext`：加载配置、环境变量、日志器。
- `CommandHandlers`：各子命令行为实现。
- `ProviderAdapter`：统一模型调用接口（便于后续扩 provider）。
- `OutputFormatter`：文本/JSON 输出。
- `SKICLIShared`：可测试的 CLI 共享逻辑（参数校验、transport 工厂、时间单位归一化），避免测试直接依赖 executable target。
  - 包含 `SKICLIExitCodeMapper`（错误到退出码映射）与 `ACPCLIOutputFormatter`（稳定 JSON 输出）。
  - `ACPClientConnectCommand` 在参数校验失败时显式抛 `ExitCode(2)`，保证进程退出码与规范一致。
  - 运行期链路错误（`ACPClientServiceError` / `ACPTransportError` / `URLError`）统一映射到 `ExitCode(4)`。

## 3. 命令草案
- `ski chat <prompt> [--model <id>] [--json]`
- `ski run <task> [--input <file>] [--json]`
- `ski config get|set <key> [value]`
- `ski version [--json]`

## 4. 配置优先级
1. CLI 参数
2. 环境变量
3. 本地配置文件（如 `~/.skintelligence/config.toml`）
4. 默认值

## 5. 错误码约定（初版）
- `0`：成功
- `2`：参数错误
- `3`：配置错误
- `4`：网络/上游调用失败
- `5`：内部未知错误

## 6. 测试策略（TDD）
- 先写失败测试：
  - 参数解析测试（命令/flag/缺参）
  - 退出码测试（成功与失败）
  - JSON 输出结构测试
  - 配置优先级测试
  - 进程级黑盒测试（直接执行 `.build/.../ski` 校验 exit code/stderr）
- 再做最小实现，通过后再重构。
- ACP/JSON-RPC 协议补充测试：
  - `jsonrpc` 版本必须为 `2.0`
  - `response` 必须且仅能携带 `result` 或 `error`
  - 非法 envelope 与非法 `id` 类型需返回解码错误
- live 网络重连回归默认 opt-in：
  - `RUN_LIVE_WS_RECONNECT_TESTS=1 swift test --filter 'SKIntelligenceTests.ACPWebSocketReconnectTests/testClientReconnectsAfterServerRestart'`
- 默认回归新增“无网络依赖”路径：
  - 通过 `WebSocketConnectionFactory` 注入脚本连接，覆盖 `send`/`receive` 两条重连路径，避免 CI 对真实网络时序敏感。

## 7. 参考仓库基线
- `/Users/linhey/Desktop/FlowUp-Libs/_cli-references/codex`
- `/Users/linhey/Desktop/FlowUp-Libs/_cli-references/gemini-cli`
- `/Users/linhey/Desktop/FlowUp-Libs/_cli-references/pi-mono`

## 8. 里程碑
- M1：`version/config get` + 测试
- M2：`chat/run` 最小闭环 + 测试
- M3：错误码、日志、JSON 稳定化

## 9. ACP WebSocket 多客户端路由（2026-02-12）
- 背景：`acp serve --transport ws` 需要支持多客户端同时接入，不能把响应误发给“最后连接”的客户端。
- 设计：
  - `WebSocketServerTransport` 维护多连接池，不再在新连接到来时踢掉旧连接。
  - 入站 `request` 在 transport 层重写为内部唯一 `id`（`s2c-<n>`），并记录 `internalID -> (connectionID, originalID)`。
  - 出站 `response` 按内部 `id` 查路由，恢复原始 `id` 后单播回对应连接。
  - 出站 `notification` 采用广播到所有在线连接。
- 风险控制：
  - 解决“多个客户端各自从 `id=1` 开始”导致的全局 `id` 冲突问题。
  - 连接关闭时清理该连接关联路由，避免状态泄漏与误投。
- 回归：
  - 新增 `ACPWebSocketMultiClientTests.testTwoClientsCanPromptConcurrentlyWithoutCrossRouting`。

## 10. ACP 业务域补齐（2026-02-12）
- `ACPClientService` 新增 `session/request_permission` 入站 request 处理：
  - 提供 `setPermissionRequestHandler` 注册点。
  - 有 handler 时按同一 `id` 回写 `response(result)`。
  - 无 handler 或未知 method 时回写 `method_not_found (-32601)`，避免悬挂请求。
- `ACPAgentService` 增加协议门禁：
  - `initialize.protocolVersion != 1` 返回 `invalid_params (-32602)`。
  - `capabilities.loadSession = false` 时，`session/load` 返回 `method_not_found (-32601)`。
- `ACPAgentService` 新增 `permissionRequester` 注入点：
  - `session/prompt` 执行前可发起权限决策。
  - `allow=false` 时短路返回 `stopReason=cancelled`，不触发模型调用与 `session/update`。
- `acp serve` 接入 `ACPPermissionRequestBridge`：
  - Agent 发起 `session/request_permission` 时由 bridge 生成 request id、发送请求、等待并匹配 response。
  - 主循环消费 `response` 并喂给 bridge，避免 permission 请求悬挂。
  - 连接结束时 `failAll(eof)` 清理 pending。
- permission 策略可配置：
  - `--permission-mode disabled|permissive|required`
  - `permissive`：bridge 异常可 fallback 放行（兼容旧 client）
  - `required`：bridge 异常不放行（严格语义）
- `acp client connect` 默认注册 permission handler（自动 allow），保证 CLI-to-CLI 基线联通。
  - 增加 `--permission-decision allow|deny` 与 `--permission-message` 便于联调。
- 新增模型：
  - `ACPSessionPermissionRequestParams`
  - `ACPSessionPermissionRequestResult`

## 11. ACP 方法域扩展（2026-02-12）
- 目标：向 ACP 官方 schema 对齐，补齐前一阶段缺失的方法域与模型字段，优先覆盖认证、会话模式/配置与 client-side 方法回调框架。
- 新增 agent-side 方法：
  - `authenticate`
  - `session/set_mode`
  - `session/set_config_option`
- 新增 client-side 方法常量与回调入口：
  - `fs/read_text_file`
  - `fs/write_text_file`
  - `terminal/create|output|wait_for_exit|kill|release`
- `ACPAgentService` 扩展：
  - 新增 `authMethods` 与 `authenticationHandler` 注入点；
  - `initialize` 响应携带 `authMethods`；
  - `session/set_mode` 产生 `session/update(current_mode_update)`；
  - `session/set_config_option` 返回 `configOptions` 且产生 `session/update(config_option_update)`。
- `ACPClientService` 扩展：
  - 新增对 incoming request 的 typed handler 分发器；
  - 支持注册 `setReadTextFileHandler`、`setWriteTextFileHandler`、`setTerminal*Handler`；
  - 对未注册 handler 的 incoming method 统一返回 `method_not_found`。
- 兼容性策略：
  - `ACPInitializeResult`、`ACPAgentCapabilities`、`ACPSessionUpdatePayload` 对新增字段采用 decode fallback（缺字段时回退默认值），避免破坏既有测试与老 payload。

## 12. ACP Stable Schema 收敛（2026-02-12）
- 目标：按 ACP stable schema 落地关键业务域，且 permission 结果采用严格新结构（不保留 `allow/message`）。
- 已收敛项：
  - `session/request_permission`：
    - 请求参数改为 `sessionId + toolCall + options`；
    - 响应改为 `outcome(cancelled|selected{optionId})`。
  - `session/new` / `session/load`：
    - 返回结构支持 `modes` 与 `configOptions` 初始状态。
  - `session/config`：
    - `configOptions` 改为 `select` 结构，含 `currentValue/options/category`。
  - `terminal/output` / `terminal/wait_for_exit`：
    - 输出响应改为 `output + truncated + exitStatus`；
    - 退出等待改为 `exitCode/signal`。
  - `acp client connect`：
    - 注册真实 `fs/read_text_file`、`fs/write_text_file`、`terminal/*` handler；
    - initialize 中显式声明 `fs` 与 `terminal` capability。
  - WebSocket server 路由：
    - 引入 `sessionId -> client connection` 绑定；
    - server-initiated request 与 session 通知按会话归属路由。

## 13. Session Update 强类型化（2026-02-12）
- 目标：将 `session/update` 从自由字符串收敛到 stable discriminator 枚举，减少协议漂移与无效 update 值。
- 变更：
  - 新增 `ACPSessionUpdateKind`，覆盖 stable 枚举值：
    - `user_message_chunk`
    - `agent_message_chunk`
    - `agent_thought_chunk`
    - `tool_call`
    - `tool_call_update`
    - `plan`
    - `available_commands_update`
    - `current_mode_update`
    - `config_option_update`
  - `ACPSessionUpdatePayload.sessionUpdate` 改为 `ACPSessionUpdateKind`。
  - 增加 `plan` 与 `availableCommands` 载荷字段，并补充 `ACPPlan*`、`ACPAvailableCommand` 模型。
- 验证：
  - 新增 `ACPModelsTests`，覆盖：
    - `plan` update encode/decode roundtrip；
    - unknown update kind 解码失败；
    - permission outcome roundtrip。

## 14. Tool Call 生命周期通知（2026-02-12）
- 目标：在 `session/prompt` 成功路径上提供可观测的 tool call 生命周期事件，便于 client 端构建进度 UI。
- 行为：
  - 成功路径按顺序发送：
    1. `session/update(tool_call)`（`status=in_progress`）
    2. `session/update(tool_call_update)`（`status=completed`）
    3. `session/update(agent_message_chunk)`（最终文本）
  - 取消/超时路径不发送上述生命周期事件，保持原有“无 message update”语义。
- 验证：
  - `ACPAgentServiceTests.testPromptEmitsToolCallLifecycleBeforeMessageChunk`
  - `ACPWebSocketRoundtripTests.testWebSocketServerClientPromptRoundtrip`（新增 update kind 顺序断言）

## 15. Plan / Available Commands 业务发射（2026-02-12）
- 目标：将 `session/update(plan)` 与 `session/update(available_commands_update)` 从“仅模型支持”推进到 agent 真实发射。
- 行为顺序（成功 prompt）：
  1. `available_commands_update`
  2. `plan`
  3. `tool_call`
  4. `tool_call_update`
  5. `agent_message_chunk`
- 约束：
  - 取消/超时/权限拒绝路径不发送上述生命周期事件。
  - websocket 回归按 update kind 顺序断言。

## 16. ToolCall 字段补齐（2026-02-12）
- 目标：对齐 ACP stable 的工具调用载荷，避免 `tool_call`/`tool_call_update` 仅有 `id/title/status` 的弱表达。
- 模型收敛：
  - 新增 `ACPToolKind`、`ACPToolCallStatus`；
  - 新增 `ACPToolCallLocation(path,line)`；
  - 新增 `ACPToolCallContent`（`content|diff|terminal`）；
  - `ACPToolCallUpdate` 扩展支持 `kind/status/content/locations/rawInput/rawOutput`。
- 兼容策略：
  - `tool_call_update` 保持增量语义，字段均可选；
  - `session/request_permission.toolCall` 继续复用 `ACPToolCallUpdate`，与 ACP SDK 行为一致。
- Agent 发射调整：
  - `tool_call` 事件默认带 `kind=execute`、`status=in_progress`、`locations=[cwd]`；
  - `tool_call_update` 事件默认仅发送 `status=completed`。

## 17. ContentBlock 扩展（2026-02-12）
- 目标：让 `session/prompt` 与 `session/update` 的内容模型不再局限于 `text`，与 ACP content 结构保持一致方向。
- 变更：
  - 新增 `ACPContentBlock` 强类型判别联合（`text|image|audio|resource_link|resource|unknown`），并将 `ACPPromptContent` / `ACPSessionUpdateContent` 统一为 typealias；
  - 提供快捷构造：`text`、`image`、`audio`、`resourceLink`。
- 兼容策略：
  - 保留原有 `type + text` 及宽字段初始化入口（通过兼容 init 映射到对应分支）；
  - 未知 `type` 进入 `unknown` 分支并原样保留 payload，避免丢失未来扩展字段；
  - 既有 prompt 拼接逻辑继续按 `text` 提取，非文本块不参与 `session.respond(to:)` 的纯文本拼接。
- 验证：
  - `ACPModelsTests.testPromptContentImageRoundTrip`
  - `ACPModelsTests.testSessionUpdateContentResourceLinkRoundTrip`
  - `ACPModelsTests.testSessionUpdateContentUnknownTypePreserved`

## 18. SessionUpdate 判别联合 + Golden 回归 + 传输一致性（2026-02-12）
- 目标：一次性收敛 ACP 三个高风险点：
  - `session/update` 业务体从“可选字段大包”收敛到“按 kind 判别”的强类型模型；
  - 建立 golden JSON fixture 双向回归，锁定协议输出；
  - 通过 stdio/ws 双链路集成测试确保业务域一致性。
- 设计：
  - 新增 `ACPSessionUpdate` 判别联合，`ACPSessionUpdatePayload` 内部以 `update` 强类型存储；
  - `encode/decode` 只读写当前 kind 对应字段，缺必需字段时解码失败；
  - 保留兼容访问器（`sessionUpdate/content/toolCall/...`）供调用方渐进迁移。
- 验证：
  - `ACPModelsTests`：新增 kind 必需字段约束测试；
  - `ACPGoldenFixturesTests`：fixture decode->encode 一致性；
  - `ACPTransportConsistencyTests`：stdio/ws update 序列一致性。

## 19. Stdio Serve 死锁修复（2026-02-12）
- 现象：`acp serve --transport stdio` 在处理 request 时若采用 `Task` 异步回写 response，可能因 `StdioTransport.receive()` 阻塞 actor 导致 `send()` 饥饿，client 侧表现为 initialize 超时。
- 修复：
  - `ACPServeCommand` 在 `stdio` 传输下改为同步处理 request 并立即回写 response；
  - `ws` 路径保持原异步处理，维持并发能力。
- 影响：
  - 修复 stdio 请求-响应闭环可用性；
  - 不改变 ws 行为。

## 20. 传输一致性测试稳态化（2026-02-12）
- 背景：`ACPTransportConsistencyTests` 之前 stdio 分支经 `ACPClientService + ProcessStdioTransport` 存在环境相关超时，需消除 flakiness。
- 调整：
  - stdio 分支改为原生 JSON-RPC 顺序校验（直接通过 transport 发送 `initialize/session/new/session/prompt` 请求并收集 `session/update`）；
  - ws 分支继续走 `ACPClientService`，覆盖实际客户端路径；
  - 一致性断言统一比较 `session/update` kind 序列。
- 结果：
  - `ACPTransportConsistencyTests` 不再依赖 skip，默认可稳定通过。

## 21. ACP Unstable Session 域补齐（2026-02-12）
- 目标：补齐 ACP unstable session 业务域核心方法，降低与官方 Kotlin SDK 的行为差距。
- 本轮实现：
  - 新增方法常量：
    - `session/list`
    - `session/resume`
    - `session/fork`
    - `session/set_model`
  - 新增模型：
    - `ACPSessionModelState` / `ACPModelInfo`
    - `ACPSessionSetModelParams/Result`
    - `ACPSessionListParams/Result`、`ACPSessionInfo`
    - `ACPSessionResumeParams/Result`
    - `ACPSessionForkParams/Result`
  - `ACPSessionCapabilities` 扩展：
    - `list` / `resume` / `fork` 三个 capability 位（nil=不支持）。
  - `ACPClientService` 扩展 API：
    - `setModel(_:)`
    - `listSessions(_:)`
    - `resumeSession(_:)`
    - `forkSession(_:)`
  - `ACPAgentService` 扩展行为：
    - `session/new|load` 返回 `models`；
    - `session/set_model` 校验模型并更新会话模型状态；
    - `session/list|resume|fork` 按 capability 门禁处理；
    - `session/fork` 返回新会话 `sessionId` 且继承模式/模型/配置状态。
  - `acp serve` 默认能力声明升级：
    - `sessionCapabilities.list/resume/fork` 默认开启。
- 验证：
  - `ACPModelsTests` 新增模型回归：
    - `testSessionSetModelParamsRoundTrip`
    - `testSessionNewResultModelsRoundTrip`
    - `testSessionListResultRoundTrip`
  - `ACPAgentServiceTests` 新增：
    - `testSetModelUpdatesCurrentModelAndLoadReflectsChange`
    - `testListResumeAndForkRequiresCapabilities`
    - `testListResumeAndForkWhenCapabilitiesEnabled`
  - `ACPClientServiceTests` 新增：
    - `testSessionDomainMethodsSetModelListResumeFork`

## 22. Session/List 分页 + Golden 扩展 + Stdio 稳定性确认（2026-02-12）
- 目标：完成检查单剩余三项并收敛为可回归状态。
- 实现：
  - `ACPAgentService.Options` 新增 `sessionListPageSize`（默认 50，最小 1）。
  - `session/list` 从占位返回改为真实 cursor 分页：
    - 请求 `cursor=nil` 从第一页开始；
    - 返回 `nextCursor`（opaque，base64 编码）拉取下一页；
    - cursor 无法解码或越界时返回 `invalid params (-32602)`。
  - `session/list` 结果排序固定为：
    - `lastTouchedNanos` 降序；
    - 相同时间戳按 `sessionId` 升序（稳定分页）。
  - 会话元数据 `updatedAt` 从“list 时即时时间”改为“会话变更时更新时间”。
  - golden fixture 扩展：
    - `available_commands_update.json`
    - `current_mode_update.json`
- 验证：
  - `swift test --filter ACPAgentServiceTests/testSessionListSupportsCursorPagination --filter ACPAgentServiceTests/testSessionListInvalidCursorReturnsInvalidParams --filter ACPGoldenFixturesTests`
  - `swift test --filter ACPTransportConsistencyTests`
  - `swift test --filter ACPModelsTests --filter ACPAgentServiceTests --filter ACPClientServiceTests --filter ACPGoldenFixturesTests --filter ACPTransportConsistencyTests`

## 23. Session/Delete + SessionInfoUpdate（2026-02-12）
- 目标：补齐 session 生命周期管理与元数据实时更新能力。
- 变更：
  - 新增 ACP 方法：
    - `session/delete`（能力位：`sessionCapabilities.delete`）。
  - 新增模型：
    - `ACPSessionDeleteParams/Result`
    - `ACPSessionDeleteCapabilities`
    - `ACPSessionInfoUpdate`
  - `ACPSessionUpdateKind` 增加 `session_info_update`，并在判别联合中新增对应分支。
  - `ACPClientService` 新增 `deleteSession(_:)` API。
  - `ACPAgentService` 新增：
    - capability 门禁 `session/delete`（未声明时 `-32601`）；
    - 删除语义幂等（不存在/重复删除也返回成功）；
    - 可选自动标题通知（`Options.autoSessionInfoUpdateOnFirstPrompt`，默认 `false`）：
      - 首次 prompt 成功后可发 `session/update(session_info_update)`，包含 `title/updatedAt`。
  - `acp serve` 默认能力声明加入 `sessionCapabilities.delete`。
  - golden fixture 新增 `session_info_update.json`。
- 验证：
  - `swift test --filter ACPAgentServiceTests/testSessionDeleteRequiresCapability --filter ACPAgentServiceTests/testSessionDeleteRemovesFromListAndIsIdempotent --filter ACPAgentServiceTests/testPromptEmitsSessionInfoUpdateAfterAutoTitleGenerated`
  - `swift test --filter ACPClientServiceTests/testSessionDomainMethodsSetModelListResumeFork --filter ACPModelsTests/testSessionDeleteParamsRoundTrip --filter ACPModelsTests/testSessionInfoUpdateRoundTrip`
  - `swift test --filter ACPGoldenFixturesTests`

## 24. 协议级取消通知 `$/cancel_request`（2026-02-12）
- 目标：对齐 ACP unstable schema 中的协议级取消通知，支持按 requestId 取消运行中的请求。
- 本轮实现：
  - `ACPMethods` 新增 `cancelRequest = "$/cancel_request"`。
  - `ACPModels` 新增 `ACPCancelRequestParams(requestId: JSONRPCID)`。
  - `ACPAgentService` 新增 request->session 映射：
    - `session/prompt` 运行期间记录 `request.id -> sessionId`；
    - 收到 `$/cancel_request` 后按 requestId 找到会话并取消对应 prompt；
    - 保留既有 `session/cancel` 语义并做映射清理。
  - `JSONRPCErrorCode` 补充 `requestCancelled = -32800` 常量，便于后续协议级错误语义落地。
- 验证：
  - `swift test --filter ACPAgentServiceTests/testPromptCanBeCancelledByProtocolCancelRequest`
  - `swift test --filter ACPModelsTests/testCancelRequestParamsRoundTrip`
  - `swift test --filter ACPModelsTests --filter ACPAgentServiceTests --filter ACPClientServiceTests --filter ACPGoldenFixturesTests --filter ACPTransportConsistencyTests`

## 25. Logout + AuthCapabilities 收口（2026-02-12）
- 目标：补齐协议方法表中 `logout` 以及 capability 门禁 `authCapabilities.logout`。
- 本轮实现：
  - `ACPMethods.logout`。
  - `ACPAgentCapabilities` 新增 `authCapabilities`，以及 `ACPAuthCapabilities.logout`。
  - 新增 `ACPLogoutParams/ACPLogoutResult`。
  - `ACPClientService` 新增：
    - `logout(_:)`
    - `cancelRequest(_:)`（发送 `$/cancel_request` 通知）
  - `ACPAgentService` 新增：
    - `logout` capability 门禁（未声明返回 `-32601`）；
    - logout 成功后清理 `sessions/runningPrompts` 等上下文。
  - 语义收敛：
    - `$/cancel_request` 命中运行中请求时，原请求返回 `-32800`。
- 验证：
  - `swift test --filter ACPAgentServiceTests/testLogoutRequiresCapability --filter ACPAgentServiceTests/testLogoutClearsSessionsWhenCapabilityEnabled`
  - `swift test --filter ACPAgentServiceTests/testPromptCanBeCancelledByProtocolCancelRequest`
  - `swift test --filter ACPClientServiceTests/testCancelRequestSendsProtocolNotification --filter ACPClientServiceTests/testSessionDomainMethodsSetModelListResumeFork`

## 26. ACP 协议一致性守卫（2026-02-12）
- 目标：避免后续改动导致 ACP 方法域与官方 schema 漂移。
- 实现：
  - 新增 `ACPMethodCatalog`：
    - `stableBaseline`
    - `unstableBaseline`
    - `projectExtensions`（显式记录非官方扩展）
    - `allSupported`
  - 引入官方快照 fixture：
    - `Tests/SKIntelligenceTests/Fixtures/acp-schema-meta/meta.json`
    - `Tests/SKIntelligenceTests/Fixtures/acp-schema-meta/meta.unstable.json`
  - 新增 `ACPProtocolConformanceTests`：
    - stable baseline 与 `meta.json` 对齐
    - unstable baseline 与 `meta.unstable.json` 对齐
    - 项目扩展严格限定为 `logout`、`session/delete`
- 验证：
  - `swift test --filter ACPProtocolConformanceTests`
  - `swift test --filter ACP --parallel`

## 27. Permission Policy 业务域（2026-02-12）
- 目标：将权限决策从临时 closure 收敛为独立业务域，对齐 pi-mono 的“可插拔门控”方向（扩展/策略驱动，而非固定硬编码流程）。
- 新增模块（`SKIACPAgent`）：
  - `PermissionPolicy/ACPPermissionPolicyMode.swift`
  - `PermissionPolicy/ACPPermissionPolicy.swift`
  - `PermissionPolicy/ACPPermissionMemoryStore.swift`
  - `PermissionPolicy/ACPToolCallFingerprint.swift`
  - `PermissionPolicy/ACPBridgeBackedPermissionPolicy.swift`
- 决策：
  - 默认策略模式采用 `ask`（由 CLI 模式映射决定）；
  - 记忆范围为 session 级，命中条件由 tool call 指纹（kind/title/locations/rawInput）决定；
  - 仅 `allow_always/reject_always` 进入记忆，`allow_once/reject_once/cancelled` 不持久化。
- `ACPAgentService` 集成：
  - 新增 `permissionPolicy` 注入点（保留 `permissionRequester` 兼容）；
  - prompt 权限选项扩展为 `allow_once/allow_always/reject_once/reject_always`；
  - `session/delete` 与 `logout` 时清理对应 session 的权限记忆。
- CLI 集成：
  - `SKICLIServePermissionMode` 新增 `policyMode` 映射：
    - `disabled -> allow`
    - `permissive|required -> ask`
  - `permissive` 保留 bridge 错误 fallback 放行；`required` 保留 bridge 错误即失败。
- 验证：
  - `swift test --filter ACPPermissionPolicyTests`
  - `swift test --filter SKICLITests/testServePermissionModeSemantics`
  - `swift test --filter ACP --parallel`

## 28. ACP Agent Telemetry（2026-02-13）
- 关联需求：`docs-dev/features/ACP-Agent-Telemetry-Spec.md`
- 目标：在不扩展 ACP JSON-RPC 方法表的前提下，提供 agent 内部可观测性事件流。
- 边界约束（强制）：
  - 协议域：仅 ACP schema 定义的方法/字段；
  - 扩展域：`ACPAgentTelemetryEvent` + `telemetrySink`，只在本地实现层生效；
  - 禁止将 telemetry 数据写入 ACP 协议 payload。
- 实现：
  - `ACPAgentService` 新增可选 `telemetrySink` 注入点；
  - 新增 `ACPAgentTelemetryEvent`（`name/sessionId/requestId/attributes/timestamp`）；
  - 生命周期事件覆盖：
    - session：`session_new/session_load/session_delete`
    - prompt：`prompt_requested/prompt_started/prompt_completed/prompt_cancelled/prompt_timed_out/prompt_failed/prompt_permission_denied`
    - retry：`prompt_retry`
- 兼容性：
  - 未注入 sink 时无行为变化；
  - telemetry 仅为内部扩展，不影响 ACP 协议交互与返回结构。
- 验证：
  - `swift test --filter ACPAgentServiceTests/testPromptEmitsTelemetryLifecycle`
  - `swift test --filter ACPAgentServiceTests/testPromptRetryEmitsTelemetryRetryEvent`
  - `swift test --filter ACPGoldenFixturesTests/testSessionUpdateGoldenFixturesRoundTrip`

## 29. 协议域/扩展域边界守卫（2026-02-13）
- 关联需求：`docs-dev/features/ACP-Protocol-Extension-Boundaries.md`
- 目标：防止 runtime/policy/telemetry 等扩展能力污染 ACP 载荷。
- 实现：
  - 在 `ACPRuntime`、`ACPClientService.installRuntimes`、`ACPPermissionPolicy` 增加 Non-ACP 边界注释；
  - 新增测试 `testTelemetryExtensionDoesNotLeakIntoProtocolPayload`：
    - 开启 telemetry 执行完整 prompt；
    - 对协议 `response/notification` 做 JSON 编码检查，确保不含 telemetry 字段与事件名。
- 验证：
  - `swift test --filter ACPAgentServiceTests/testTelemetryExtensionDoesNotLeakIntoProtocolPayload`
