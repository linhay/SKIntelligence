# ACP 业务域落地检查单（2026-02-12）

关联：
- `docs-dev/features/ACP-WebSocket-Serve-Spec.md`
- `docs-dev/dev/CLI-Architecture-Plan.md`

## 1. 本次变更范围
- `session/update` 业务体改为判别联合（按 `sessionUpdate` kind 强约束）。
- 增加 ACP golden JSON fixture 双向回归。
- 增加 ws/stdio 业务序列一致性集成回归（stdio 在当前环境不可用时跳过）。
- 修复 `acp serve --transport stdio` 请求处理死锁风险（stdio 路径改为同步回写 response）。
- 补齐 ACP unstable session 域核心方法：
  - `session/list`
  - `session/resume`
  - `session/fork`
  - `session/set_model`
- `session/new|session/load` 返回补齐 `models` 状态；`acp serve` 默认声明 `list/resume/fork` capability。

## 2. 验证命令
```bash
swift test --filter ACPModelsTests --filter ACPAgentServiceTests --filter ACPClientServiceTests
swift test --filter ACPGoldenFixturesTests --filter ACPTransportConsistencyTests
swift test --filter ACPWebSocketPermissionRoundtripTests/testPermissionApprovedAllowsPrompt
```

## 3. 通过标准
- `ACPModelsTests` 全通过：
  - 覆盖 `plan`/`agent_message_chunk` 必需字段约束；
  - 覆盖 tool call 扩展字段与 content block 兼容。
- `ACPGoldenFixturesTests` 通过：
  - fixture `decode -> encode` 结果一致。
- `ACPTransportConsistencyTests`：
  - 断言 ws/stdio 序列一致；
  - 当前实现已改为 stdio 原生 JSON-RPC 顺序收发校验，默认不再依赖 skip。
- 新增 unstable session 方法验证：
  - agent 侧覆盖 capability 门禁与成功路径；
  - client 侧覆盖 `setModel/listSessions/resumeSession/forkSession` 调用链路；
  - models 编解码 roundtrip 通过。

## 4. 风险与回滚
- 风险：`ACPSessionUpdatePayload` 已从宽松“可选字段大包”收敛为按 kind 严格解码，外部非规范 payload 将被拒绝。
- 回滚：如需放宽，可在 `ACPSessionUpdatePayload.init(from:)` 恢复 `decodeIfPresent` 并设默认值（不建议，易放大协议漂移）。
- 现状：`ACPTransportConsistencyTests` 已稳定通过（stdio+ws 一致性）。
- 现状：`ACPWebSocketPermissionRoundtripTests` 在全量并发执行时偶发端口占用（`Address already in use`），单测重跑可通过，属环境端口竞争而非业务逻辑回归。

## 5. 后续动作
- [x] 排查 stdio 子进程 `initialize` 超时根因：
  - 现状：`ACPTransportConsistencyTests` 已在 stdio + ws 双链路稳定通过，不再依赖 skip。
- [x] 扩展 golden fixture：
  - 已新增 `available_commands_update` 与 `current_mode_update` 并纳入 roundtrip 回归。
- [x] 将 `session/list` 的 `cursor/nextCursor` 推进到真实分页：
  - 已实现 opaque cursor 分页；
  - 无效/越界 cursor 返回 `invalid params (-32602)`；
  - 已补充分页与错误语义测试。

## 6. 新增收敛（本轮）
- `session/delete` 已落地：
  - 新增 `sessionCapabilities.delete` 能力位；
  - 能力关闭返回 `method not found (-32601)`；
  - 删除语义幂等，删除后不再出现在 `session/list`。
- `session_info_update` 已落地：
  - `ACPSessionUpdateKind` 新增 `session_info_update`；
  - 新增 `ACPSessionInfoUpdate(title, updatedAt)`；
  - agent 支持可选自动标题通知（默认关闭，避免影响现有生命周期序列）。
- 验证命令：
```bash
swift test --filter ACPAgentServiceTests/testSessionDeleteRequiresCapability \
  --filter ACPAgentServiceTests/testSessionDeleteRemovesFromListAndIsIdempotent \
  --filter ACPAgentServiceTests/testPromptEmitsSessionInfoUpdateAfterAutoTitleGenerated

swift test --filter ACPClientServiceTests/testSessionDomainMethodsSetModelListResumeFork \
  --filter ACPModelsTests/testSessionDeleteParamsRoundTrip \
  --filter ACPModelsTests/testSessionInfoUpdateRoundTrip \
  --filter ACPGoldenFixturesTests
```

## 7. 协议级取消 `$/cancel_request`（本轮）
- 新增方法常量：`ACPMethods.cancelRequest = "$/cancel_request"`。
- 新增参数模型：`ACPCancelRequestParams(requestId)`。
- `ACPAgentService` 取消逻辑增强：
  - 维护运行中 prompt 的 `request.id -> sessionId` 映射；
  - 收到 `$/cancel_request` 后按 requestId 定位并取消对应 prompt；
  - 与既有 `session/cancel` 共存，均会清理映射。
- 验证命令：
```bash
swift test --filter ACPAgentServiceTests/testPromptCanBeCancelledByProtocolCancelRequest \
  --filter ACPAgentServiceTests/testPromptCanBeCancelled \
  --filter ACPModelsTests/testCancelRequestParamsRoundTrip

swift test --filter ACPModelsTests --filter ACPAgentServiceTests --filter ACPClientServiceTests \
  --filter ACPGoldenFixturesTests --filter ACPTransportConsistencyTests
```

## 8. Logout + -32800 语义收口（本轮）
- 新增 `logout` 与 capability：
  - `ACPMethods.logout`
  - `ACPAgentCapabilities.authCapabilities.logout`
  - `ACPLogoutParams/ACPLogoutResult`
- `ACPAgentService`：
  - capability 门禁 `logout`（未声明 -> `-32601`）
  - `logout` 成功后清理会话与运行任务上下文
- `$/cancel_request` 语义收敛：
  - 命中运行中 request 时，原请求返回 `-32800`（request cancelled）
- 验证命令：
```bash
swift test --filter ACPAgentServiceTests/testLogoutRequiresCapability \
  --filter ACPAgentServiceTests/testLogoutClearsSessionsWhenCapabilityEnabled \
  --filter ACPAgentServiceTests/testPromptCanBeCancelledByProtocolCancelRequest

swift test --filter ACPClientServiceTests/testCancelRequestSendsProtocolNotification \
  --filter ACPClientServiceTests/testSessionDomainMethodsSetModelListResumeFork \
  --filter ACPModelsTests/testLogoutParamsRoundTrip
```

## 9. 协议一致性守卫（本轮）
- 新增 `ACPMethodCatalog`，显式分层：
  - `stableBaseline`
  - `unstableBaseline`
  - `projectExtensions`（仅 `logout`、`session/delete`）
- 新增官方 schema 快照 fixture：
  - `Fixtures/acp-schema-meta/meta.json`
  - `Fixtures/acp-schema-meta/meta.unstable.json`
- 新增 `ACPProtocolConformanceTests`：
  - 稳定方法集对齐 `meta.json`
  - unstable 方法集对齐 `meta.unstable.json`
  - 项目扩展范围守卫
- 验证命令：
```bash
swift test --filter ACPProtocolConformanceTests
swift test --filter ACP --parallel
```

## 10. Permission Policy 业务域（本轮）
- 新增 `SKIACPAgent/PermissionPolicy` 模块：
  - `ACPPermissionPolicyMode`（ask/allow/deny）
  - `ACPPermissionPolicy` 协议
  - `ACPPermissionMemoryStore`（session 级记忆）
  - `ACPToolCallFingerprint`（kind/title/locations/rawInput 规范化指纹）
  - `ACPBridgeBackedPermissionPolicy`（bridge + 模式 + 记忆）
- `ACPAgentService` 接入：
  - 新增 `permissionPolicy` 注入点（保持旧 `permissionRequester` 兼容）；
  - prompt 权限选项补齐 `allow_always/reject_always`；
  - `session/delete` 与 `logout` 清理权限记忆。
- CLI 收敛：
  - `SKICLIServePermissionMode.policyMode` 映射：
    - `disabled -> allow`
    - `permissive|required -> ask`
  - `permissive`：bridge 错误 fallback allow；
  - `required`：bridge 错误直接失败。
- 验证命令：
```bash
swift test --filter ACPPermissionPolicyTests
swift test --filter SKICLITests/testServePermissionModeSemantics
swift test --filter ACP --parallel
```

## 11. Runtime 与 Session Persistence 业务域（本轮新增）
- 新增 `SKIACPClient` Runtime 抽象：
  - `ACPFilesystemRuntime` / `ACPLocalFilesystemRuntime`
  - `ACPTerminalRuntime` / `ACPProcessTerminalRuntime`
  - `ACPRuntimeError` 与 rooted 文件访问策略
- 新增 `ACPClientService.installRuntimes(filesystem:terminal:)` 统一接线接口。
- `SKICLI` 改造为复用 runtime 抽象，移除内嵌 terminal registry 实现。
- `SKIAgentSession` 新增 `enableJSONLPersistence(fileURL:configuration:)`，支持跨 session 恢复 transcript。
- 新增测试：
  - `ACPClientRuntimeTests`
  - `SKIAgentSessionTests/testEnableJSONLPersistenceRestoresTranscriptAcrossSessions`

验证命令：
```bash
swift test --filter ACPClientRuntimeTests \
  --filter SKIAgentSessionTests/testEnableJSONLPersistenceRestoresTranscriptAcrossSessions

swift test --filter ACP --filter SKICLITests --filter SKICLIProcessTests --filter SKIAgentSessionTests
```

## 12. Permission Policy 细节收敛（本轮补充）
- 记忆命中 `reject_always` 时，策略结果统一返回 `cancelled`（避免调用方解析 `selected(reject_always)` 分支歧义）。
- 补齐测试覆盖：
  - `allow_once` 不应进入记忆（第二次仍请求 requester）
  - `reject_always` 进入记忆后应短路为 `cancelled`

验证命令：
```bash
swift test --filter ACPPermissionPolicyTests
swift test --filter ACPAgentServiceTests --filter ACPClientRuntimeTests --filter SKIAgentSessionTests
```

## 13. Session Fork 真实复制语义（本轮新增）
- `ACPAgentSession` 扩展：
  - `snapshotEntries()`
  - `restoreEntries(_:)`
- `ACPAgentService.sessionFork` 改为：
  1) 从源 session 提取 transcript 快照
  2) 通过 `sessionFactory` 创建新 session
  3) 将快照恢复到新 session
- 行为结果：fork 后新会话继承源上下文，同时与源会话保持隔离。
- 新增测试：`ACPAgentServiceTests/testForkCopiesSessionStateAndKeepsIsolation`。

验证命令：
```bash
swift test --filter ACPAgentServiceTests/testForkCopiesSessionStateAndKeepsIsolation \
  --filter ACPAgentServiceTests/testListResumeAndForkWhenCapabilitiesEnabled

swift test --filter ACPAgentServiceTests --filter ACPPermissionPolicyTests --filter ACPClientRuntimeTests
```

## 14. Session Load + JSONL 自动接线（本轮新增）
- `ACPAgentService.Options` 新增 `sessionPersistence`：
  - `directoryURL`
  - `configuration(maxReadBytes)`
- `ACPAgentSession` 新增可选持久化能力协议 `ACPPersistableAgentSession`。
- `SKIAgentSession` 对齐实现 `ACPPersistableAgentSession`，用于接入 `enableJSONLPersistence`。
- `ACPAgentService` 接入策略：
  - `session/new`：若配置了 `sessionPersistence`，自动将新会话绑定到 `<directory>/<sessionId>.jsonl`。
  - `session/fork`：分叉会话创建后自动绑定其 JSONL 文件。
  - `session/load`：当内存中不存在 session 时，若磁盘存在 `<sessionId>.jsonl`，自动创建并恢复会话；否则保持 `sessionNotFound` 语义。
- 新增测试：
  - `ACPAgentServiceTests/testSessionLoadRestoresPersistedTranscriptWhenSessionNotInMemory`

验证命令：
```bash
swift test --filter ACPAgentServiceTests/testSessionLoadRestoresPersistedTranscriptWhenSessionNotInMemory
swift test --filter ACPAgentServiceTests --filter ACPPermissionPolicyTests --filter ACPClientRuntimeTests
```

## 15. Prompt 执行状态机（A1+A3，第一批）
- `ACPModels` 新增会话更新判别值：
  - `execution_state_update`
  - `retry_update`（预留）
  - `audit_update`（预留）
- `ACPModels` 新增强类型载荷：
  - `ACPExecutionState/ACPExecutionStateUpdate`
  - `ACPRetryUpdate`
  - `ACPAuditUpdate`
- `ACPAgentService.Options` 新增 `promptExecution.enableStateUpdates`（默认 `false`，保持兼容）。
- `ACPAgentService` 在 `session/prompt` 中接入状态发射：
  - `queued`（进入 prompt）
  - `running`（开始执行）
  - `completed`（成功结束）
  - `cancelled`（取消或权限拒绝）
  - `timed_out`（超时）
  - `failed`（未知失败）
- 新增测试：
  - `ACPModelsTests/testExecutionStateUpdateRoundTrip`
  - `ACPAgentServiceTests/testPromptEmitsExecutionStateLifecycleWhenEnabled`
  - `ACPAgentServiceTests/testPromptCancellationEmitsExecutionStateWhenEnabled`

验证命令：
```bash
swift test --filter ACPModelsTests/testExecutionStateUpdateRoundTrip \
  --filter ACPAgentServiceTests/testPromptEmitsExecutionStateLifecycleWhenEnabled \
  --filter ACPAgentServiceTests/testPromptCancellationEmitsExecutionStateWhenEnabled

swift test --filter ACPModelsTests --filter ACPAgentServiceTests --filter ACPClientRuntimeTests --filter ACPTransportConsistencyTests
```

## 16. Prompt 重试策略（A2）
- `ACPAgentService.Options.PromptExecution` 扩展：
  - `maxRetries`（默认 0）
  - `retryBaseDelayNanoseconds`（默认 100ms）
- `session/prompt` 执行路径新增重试循环（保持取消/超时优先语义）：
  - `CancellationError`：立即终止，不重试；
  - `promptTimedOut`：立即终止，不重试；
  - 其他错误：在 `maxRetries` 范围内退避重试。
- 状态与可观测：
  - 重试时发射 `execution_state_update(state=retrying)`；
  - 同时发射 `retry_update(attempt,maxAttempts,reason)`；
  - 耗尽后发射 `execution_state_update(state=failed)`。
- 新增测试：
  - `ACPAgentServiceTests/testPromptRetriesThenSucceedsWhenConfigured`
  - `ACPAgentServiceTests/testPromptRetryExhaustedReturnsInternalError`
  - `ACPModelsTests/testRetryUpdateRoundTrip`

验证命令：
```bash
swift test --filter ACPModelsTests/testRetryUpdateRoundTrip \
  --filter ACPAgentServiceTests/testPromptRetriesThenSucceedsWhenConfigured \
  --filter ACPAgentServiceTests/testPromptRetryExhaustedReturnsInternalError

swift test --filter ACPModelsTests --filter ACPAgentServiceTests --filter ACPClientRuntimeTests --filter ACPTransportConsistencyTests
```

## 17. FS Runtime Policy 细化（B1 第一批）
- `ACPFilesystemAccessPolicy` 新增：
  - `.rootedWithRules(ACPFilesystemRootedRules)`
- `ACPFilesystemRootedRules` 能力：
  - `readOnlyRoots`：写入拒绝；
  - `deniedPathPrefixes`：按 rooted 相对前缀拒绝访问。
- `ACPLocalFilesystemRuntime` 校验逻辑：
  - 先执行 rooted 边界检查；
  - 再执行 deny prefix；
  - 写入路径额外执行 read-only root 检查。
- 新增测试：
  - `ACPClientRuntimeTests/testLocalFilesystemRuntimeRootedRulesReadOnlyAndDeniedPrefixes`

验证命令：
```bash
swift test --filter ACPClientRuntimeTests/testLocalFilesystemRuntimeRootedRulesReadOnlyAndDeniedPrefixes \
  --filter ACPClientRuntimeTests/testLocalFilesystemRuntimeReadWriteAndRootPolicy

swift test --filter ACPModelsTests --filter ACPAgentServiceTests --filter ACPClientRuntimeTests --filter ACPTransportConsistencyTests
```
