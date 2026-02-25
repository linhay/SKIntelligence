
## Live Provider Tests 开关约定（2026-02-17）
- 目标：避免外部 API 波动导致默认 `swift test` 不稳定。
- 约定：依赖外部模型/网络/第三方密钥的测试，统一通过环境变量 `RUN_LIVE_PROVIDER_TESTS=1` 显式开启。
- 默认行为：未设置该环境变量时，相关测试应快速返回，不触发外部调用。
- 当前覆盖：
  - `Tests/SKIntelligenceTests/TavilySearchTest.swift`
  - `Tests/SKIntelligenceTests/MedicalReportTests.swift`
  - `Tests/SKIntelligenceTests/GameTests.swift`
- 手动运行：`RUN_LIVE_PROVIDER_TESTS=1 swift test`

## ACP 端到端矩阵（2026-02-17）
- 目标：用同一业务契约同时覆盖两条 transport 链路，避免“单链路通过、跨链路偏差”。
- 覆盖测试：`Tests/SKIntelligenceTests/ACPDomainE2EMatrixTests.swift`
- 当前矩阵维度：
  - `stdioInProcess`（内存双端 transport + ACPClientService + ACPAgentService）
  - `wsInProcess`（WebSocketClientTransport + WebSocketServerTransport）
- 已锁定契约：
  - 初始化/认证：`initialize -> authenticate` 返回协议版本与 `authMethods` 一致
  - 会话分页：`session/new x3 -> session/list(cursor)` 可完整枚举并保持唯一性
  - 模型切换恢复：`session/set_model -> session/load -> session/resume` 保持 `currentModelId` 一致
  - 运行中取消：`session/prompt(in-flight) -> session/cancel` 返回 `stopReason=cancelled`
  - 权限拒绝路径：`session/prompt` 返回 `stopReason=cancelled`
  - 会话域路径：`session/new -> session/prompt -> session/fork -> session/load -> session/export`
  - fork 后对话连续性：`session/fork -> session/prompt` 在 stdio/ws 文本输出一致
- 收敛状态：
  - `$/cancel_request` 的 transport E2E 矩阵已纳入：`ACPDomainE2EMatrixTests/testCancelRequestPromptContractConsistentBetweenStdioAndWebSocket`。
  - 服务层权限阶段竞态回归已覆盖：`ACPAgentServiceTests/testPromptCanBeCancelledByProtocolCancelRequestDuringPermissionStage`。
  - ws 入站 `$/cancel_request.requestId` 重映射能力已由 `ACPWebSocketRoutingTests` 锁定行为。

## ACP `$/cancel_request` 矩阵收口（2026-02-17）
- 新增跨 transport 契约：`ACPDomainE2EMatrixTests/testCancelRequestPromptContractConsistentBetweenStdioAndWebSocket`。
- 覆盖链路：`initialize -> session/new -> session/prompt(in-flight) -> $/cancel_request`。
- 断言：stdio 与 ws 都返回 JSON-RPC `error.code = requestCancelled`（`-32800`）。
- 实现要点：该用例使用原始 JSON-RPC request/notification（不走 `ACPClientService.cancel`），直接验证协议级 `$/cancel_request` 行为。
- 结论：此前“`$/cancel_request` E2E 待收敛”项已完成并纳入矩阵常规回归。
- 权限阶段补强：新增 `ACPDomainE2EMatrixTests/testCancelRequestDuringPermissionContractConsistentBetweenStdioAndWebSocket`，覆盖 `session/request_permission` 阶段收到 `$/cancel_request` 的竞态窗口，stdio/ws 同步返回 `requestCancelled`。

## ACP 回归稳定性备注（2026-02-17）
- 在一次 `swift test --filter ACP` 全量回归中，`ACPClientRuntimeTests/testProcessTerminalRuntimeLifecycle` 出现单次波动失败；立即单测重跑通过。
- 判定：与本轮 `$/cancel_request` 改动无直接耦合，暂作为 runtime 测试稳定性观察项持续跟踪。

## ACP Runtime 稳定性修复（2026-02-17）
- 现象：`ACPClientRuntimeTests/testProcessTerminalRuntimeLifecycle` 偶发在 `waitForExit` 后读取不到完整输出。
- 根因：进程退出事件与 `readabilityHandler` 异步追加输出之间存在时序窗口。
- 修复：`ACPProcessTerminalRuntime.markExit` 在退出回调中先关闭 `readabilityHandler`，再 `readDataToEndOfFile()` 主动 flush 尾部输出后再唤醒 waiters。
- 新增回归：`ACPClientRuntimeTests/testProcessTerminalRuntimeWaitForExitFlushesRemainingOutput`，验证 `waitForExit` 返回后输出缓冲已完整。
- 回归结果：`swift test --filter ACPClientRuntimeTests` 与 `swift test --filter ACP --filter SKICLITests` 均通过。

## ACP `$/cancel_request` 字符串 requestId 兼容性（2026-02-17）
- 新增矩阵用例：`ACPDomainE2EMatrixTests/testCancelRequestPromptWithStringRequestIDContractConsistentBetweenStdioAndWebSocket`。
- 覆盖链路：原始 JSON-RPC `request.id` 使用字符串，`$/cancel_request.params.requestId` 也使用字符串。
- 断言：stdio 与 ws 两条链路均返回 `requestCancelled`，避免仅 numeric id 覆盖导致的协议盲点。
- transport 锁定：新增 `ACPWebSocketRoutingTests/testCancelRequestNotificationStringRequestIDIsRemappedToInternalID`，验证 ws 路由层会把外部字符串 requestId 正确映射到内部 `s2c-*` id。

## ACP WebSocket 多客户端并发压力补强（2026-02-17）
- 新增用例：`ACPWebSocketMultiClientTests/testFiveClientsCanPromptConcurrentlyWithoutCrossRouting`。
- 场景：5 个 ws 客户端并发执行 `session/prompt`，逐一校验 `stopReason=endTurn` 与各自 `session/update` 文本命中。
- 目标：放大多客户端并发路由压力，确保没有跨会话/跨连接串扰。
- 回归：`swift test --filter ACPWebSocketMultiClientTests` 与 `swift test --filter ACP --filter SKICLITests` 均通过。

## ACP `cancel_request` fallback 双向语义补齐（2026-02-17）
- 新增服务层回归：
  - `ACPAgentServiceTests/testPromptPreCancelledByProtocolStringRequestIDMatchesIntPromptID`
  - `ACPAgentServiceTests/testPromptPreCancelledByProtocolIntRequestIDMatchesStringPromptID`
- 覆盖场景：`$/cancel_request` 先到达，随后 `session/prompt` 才到达；验证 `int <-> s2c-*` 双向 fallback 都能命中并返回 `requestCancelled`。
- 目的：锁住 requestId 映射兼容性，避免 ws 内部 id 重写路径回退。

## ACP `cancel_request` pre-cancel 端到端矩阵（2026-02-17）
- 新增矩阵用例：`ACPDomainE2EMatrixTests/testPreCancelRequestPromptContractConsistentBetweenStdioAndWebSocket`。
- 覆盖场景：`$/cancel_request` 先到，`session/prompt` 后到（pre-cancel）。
- 覆盖 id 组合：
  - `requestId: "s2c-3"` -> `prompt.id: 3`（string -> int）
  - `requestId: 4` -> `prompt.id: "s2c-4"`（int -> string）
- 断言：stdio/ws 均返回 `requestCancelled`，并保持跨 transport 一致。

## ACP WebSocket client runtime 回调 E2E 补齐（2026-02-17）
- 关联规格：`docs-dev/features/ACP-WebSocket-Serve-Spec.md` 场景 33-36、40-41。
- 新增测试：`Tests/SKIntelligenceTests/ACPWebSocketClientRuntimeRoundtripTests.swift`。
- 新增契约：
  - `testAgentCanInvokeClientFSAndTerminalRuntimesOverWebSocket`
  - `testKilledTerminalCanStillOutputUntilReleaseOverWebSocket`
- 覆盖链路：
  - `fs/read_text_file`：按 `line/limit` 读取返回文本。
  - `fs/write_text_file`：写入成功并可从磁盘读取回写内容。
  - `terminal/create -> wait_for_exit -> output -> release`：返回生命周期结果与 `exitStatus`。
  - `terminal/kill -> output`（未 release）：仍可读取最终输出；`release` 后再次 `output` 返回错误（terminalId 失效）。
- 收敛价值：从“本地 runtime 单测”提升到“真实 ws 传输 + 客户端 runtime 回调”端到端保障。

## ACP Runtime 回调纳入跨 transport 契约矩阵（2026-02-17）
- 新增矩阵用例：
  - `ACPDomainE2EMatrixTests/testRuntimeFSAndTerminalLifecycleContractConsistentBetweenStdioAndWebSocket`
  - `ACPDomainE2EMatrixTests/testRuntimeTerminalKillContractConsistentBetweenStdioAndWebSocket`
- 覆盖协议链路：
  - `fs/read_text_file`（含 `line/limit`）
  - `fs/write_text_file`
  - `terminal/create -> wait_for_exit -> output -> release`
  - `terminal/kill -> output`（未 release 仍可读最终输出）
  - `release` 后 `terminal/output` 返回错误（terminalId 失效）
- 基础设施补充：`InProcessMatrixHarness` 增加可选 response 回调，用于捕获 server->client request 的响应并断言 stdio/ws 一致性。
- 回归结果：`swift test --filter ACP --filter SKICLITests` 通过（161 passed, 1 skipped）。

## ACP-WebSocket-Serve 规格场景映射（2026-02-17）
- 参考规格：`docs-dev/features/ACP-WebSocket-Serve-Spec.md`
- 状态说明：`已覆盖` / `部分覆盖` / `待补充`

### 已覆盖（核心链路）
- 场景 1/19/20/21：
  - `ACPWebSocketRoundtripTests/testWebSocketServerClientPromptRoundtrip`
  - `ACPWebSocketMultiClientTests/testTwoClientsCanPromptConcurrentlyWithoutCrossRouting`
  - `ACPWebSocketMultiClientTests/testFiveClientsCanPromptConcurrentlyWithoutCrossRouting`
  - `ACPWebSocketMultiClientTests/testServerNotificationBroadcastsToAllConnectedClients`
- 场景 3：
  - `ACPWebSocketTestHarnessTests/testServerSendWithoutConnectedClientReturnsNotConnected`
- 场景 4/17：
  - `ACPWebSocketClientDeterministicReconnectTests/testSendRetriesWithReconnectUsingInjectedFactory`
  - `ACPWebSocketClientDeterministicReconnectTests/testReceiveRetriesWithReconnectUsingInjectedFactory`
- 场景 5/16：
  - `ACPTransportResilienceTests/testBackpressureGateBlocksUntilRelease`
  - `ACPTransportResilienceTests/testBackpressureGateCancelledWaiterDoesNotLeakPermit`
- 场景 6：
  - `JSONRPCCodecTests` 大包 line framer 回环（`512 * 1024`）
- 场景 7~15：
  - `ACPClientServiceTests`（并发/乱序/close/timeout/id 连续性/长跑清理）
  - `ACPAgentServiceTests/testPromptWhileRunningReturnsInvalidParams`
- 场景 22/25/26/28/29/37：
  - `ACPWebSocketPermissionRoundtripTests`（allow/deny）
  - `ACPPermissionPolicyTests`（allow/deny/ask/permissive/required/记忆）
  - `ACPPermissionRequestBridgeTests`（success/rpcError/timeout/failAll 清理）
- 场景 27：
  - `ACPWebSocketPermissionRoundtripTests/testPendingPermissionRequestFailsFastWhenTransportCloses`
  - `ACPPermissionRequestBridgeTests/testFailAllClearsPendingPermissionRequests`
- 场景 23/24/30/31/32：
  - `ACPAgentServiceTests` 初始化版本校验、load capability 门禁、authenticate、set_mode、set_config_option
- 场景 33/34/35/36/40/41：
  - `ACPWebSocketClientRuntimeRoundtripTests`
  - `ACPDomainE2EMatrixTests/testRuntimeFSAndTerminalLifecycleContractConsistentBetweenStdioAndWebSocket`
  - `ACPDomainE2EMatrixTests/testRuntimeTerminalKillContractConsistentBetweenStdioAndWebSocket`
- 场景 42/43/44/45/46/47/55：
  - `ACPWebSocketRoundtripTests`（update 顺序）
  - `ACPModelsTests`（tool_call/tool_call_update/content block/判别联合）
  - `ACPGoldenFixturesTests/testSessionUpdateGoldenFixturesRoundTrip`
- 场景 48：
  - `ACPTransportConsistencyTests/testSessionUpdateSequenceConsistentBetweenStdioAndWebSocket`
- 场景 49~54/56~58/63（export）/64（fork parent）：
  - `ACPDomainE2EMatrixTests`（set_model/list/resume/fork/list cursor/fork-load-export）
  - `ACPAgentServiceTests`（delete/session_info_update/export/list parentSessionId）
- 场景 59/60/61/62：
  - `ACPAgentServiceTests`（cancel_request / logout）
  - `ACPWebSocketRoutingTests`（cancel_request requestId 重映射）
  - `ACPProtocolConformanceTests`（meta 快照一致性）
- 场景 63/64（端口冲突与资源清理）：
  - `ACPWebSocketTestHarnessTests/testMakeServerTransportRetriesWhenPreferredPortIsOccupied`
  - 现有 ws 集成测试均在 `defer` 中关闭 client/server/loop
- 场景 63~66（execution_state/retry/permission policy 扩展段）：
  - `ACPAgentServiceTests/testPromptEmitsExecutionStateLifecycleWhenEnabled`
  - `ACPAgentServiceTests/testPromptCancellationEmitsExecutionStateWhenEnabled`
  - `ACPAgentServiceTests/testPromptRetriesThenSucceedsWhenConfigured`
  - `ACPAgentServiceTests/testPromptRetryExhaustedReturnsInternalError`
  - `ACPPermissionPolicyTests`（allow/deny/ask 记忆与 delete/logout 清理）

### 部分覆盖（建议补强）
- 场景 2（stdio 既有行为不变）：
  - 目前由 `ACPDomainE2EMatrixTests` stdio 分支覆盖核心行为。
  - 若要做“CLI 级不变性”可增加 `ski acp serve --transport stdio` 的进程级快照测试。

### 待补充（当前无强约束用例）
- 无阻塞级别缺口；当前 ACP 主流程与 runtime/permission/cancel/matrix 已形成闭环回归。

## ACP 门禁与覆盖矩阵资产化（2026-02-17）
- 新增覆盖矩阵文档：`docs-dev/dev/ACP-Spec-Coverage-Matrix.md`（spec 场景到测试映射）。
- 新增映射守卫测试：`Tests/SKIntelligenceTests/ACPSpecCoverageMatrixTests.swift`。
  - 校验文档中 `SKIntelligenceTests.<Class>/<testMethod>` 引用存在于对应测试文件。
  - 校验文档中显式文件路径（`Tests/SKIntelligenceTests/*.swift`）可解析存在。
- 新增门禁脚本：`scripts/test_acp_gate.sh`。
  - 统一执行 `ACP + SKICLITests + SKICLIProcessTests + JSONRPCCodecTests`。
- 新增 stdio 进程级不变性测试：
  - `SKICLIProcessTests/testClientConnectViaStdioServeProcessSucceeds`（`client connect --transport stdio` + `--cmd ski --args acp serve --transport stdio`）。
