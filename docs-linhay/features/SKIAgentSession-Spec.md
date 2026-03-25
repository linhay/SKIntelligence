# SKIAgentSession 功能规格（最小版）

## 背景
当前 `SKILanguageModelSession` 已具备对话与工具循环能力，但缺少面向 ACP 业务域的统一会话门面：
- 会话 ID
- fork/resume 生命周期能力
- 显式取消当前 prompt
- 统一工具注册入口

## 验收场景（BDD）

### 场景 1：基础会话 prompt
- Given 一个新的 `SKIAgentSession`
- When 调用 `prompt("hello")`
- Then 返回 assistant 文本
- And transcript 中追加了用户与 assistant 记录

### 场景 2：fork 会话
- Given 原会话已有历史记录
- When 调用 `fork()`
- Then 新会话拥有独立 sessionId
- And 新会话初始 transcript 与原会话快照一致
- And 新会话后续消息不会污染原会话

### 场景 3：resume 会话
- Given 一组已保存的 transcript entries
- When 对新会话调用 `resume(with:)`
- Then 新会话 transcript 等于该快照

### 场景 4：取消进行中的 prompt
- Given 当前会话正在执行慢响应 prompt
- When 调用 `cancelActivePrompt()`
- Then prompt 抛出取消错误

### 场景 5：列出可分叉的用户消息
- Given 会话中已有多轮 user/assistant 对话
- When 调用 `forkableUserMessages()`
- Then 返回按 transcript 顺序排列的用户消息列表
- And 每个元素包含 `entryIndex` 与对应文本

### 场景 6：从指定用户消息分叉
- Given 会话中已有三轮用户消息
- When 调用 `fork(fromUserEntryIndex:)` 并选择第二轮用户消息
- Then 新会话仅保留该消息之前的上下文
- And 原会话内容不被修改
- And 新会话后续消息仍与原会话隔离

### 场景 7：运行中消息排队（steer/followUp）
- Given 当前 prompt 正在执行
- When 调用 `prompt(..., streamingBehavior: .followUp)` 或 `steer()/followUp()`
- Then 消息进入待处理队列而不是抛错
- And 当前 prompt 完成后按顺序继续执行队列
- And `pendingMessageCount()` 最终回到 0

### 场景 8：工具清单与启用状态
- Given 会话注册了多个工具且包含禁用工具
- When 调用 `toolDescriptors()` 与 `activeToolNames()`
- Then 返回工具名称、描述、短描述、参数 schema 与来源类型
- And `activeToolNames()` 仅包含当前启用工具
- When 调用 `unregister(toolNamed:)`
- Then 工具清单与 active 列表同步更新

### 场景 9：Transcript 事件结构化上下文
- Given transcript 中包含 message/toolCall/toolOutput 多类 entry
- When 调用 `events()`
- Then 每个事件包含 `source`（transcript/session）与 `entryIndex`（来自 transcript 时）
- And 同一 entry 派生的多个事件共享相同 `entryIndex`

### 场景 10：会话统计视图
- Given 会话执行过 prompt 且包含工具调用
- When 调用 `stats()`
- Then 返回 `userMessages/assistantMessages/toolCalls/toolResults/totalEntries/pendingMessages`
- And 包含 `pendingBreakdown(prompt_follow_up/steer/follow_up)` 分组计数
- And 返回 `lastUpdatedAt`（空会话为 nil，有交互后为最新更新时间）
- And 统计结果与 transcript 当前状态一致

### 场景 11：待处理队列快照可观测
- Given 当前 prompt 正在执行且后续有 `prompt(..., followUp)`、`steer()`、`followUp()` 入队
- When 调用 `pendingMessages()` 或 `pendingMessages(maxLength:)`
- Then 返回按入队顺序的快照
- And 每条快照包含来源类型（`prompt_follow_up/steer/follow_up`）与文本预览
- And 可选包含最近已处理项（`includeResolved=true`，标记 `resolved/failed`）
- And 文本预览采用统一长度策略（超过 120 字符时截断并追加 `...`）

### 场景 13：Pending 状态清理
- Given 会话中存在 queued 与 resolved pending 项
- When 调用 `clearPendingHistory()`
- Then 仅清理 resolved 历史，不影响当前 queued 队列
- When 调用 `clearPendingState()`
- Then queued 与 resolved 同时清理
- And 对等待中的 followUp continuation 返回取消错误
- When 调用 `clearPendingState(cancelActivePrompt: true)`
- Then 当前运行中的 prompt 也应被取消

### 场景 12：待处理来源分组统计
- Given 当前会话存在多来源 pending 消息
- When 调用 `stats()`
- Then `pendingBreakdown` 应分别返回 `prompt_follow_up/steer/follow_up` 的数量
- And pending 执行完成后三类计数归零

### 场景 14：空闲会话 followUp 不应重复执行
- Given 当前会话没有进行中的 prompt
- When 调用 `followUp("...")`
- Then 应直接触发一次执行
- And transcript 中该用户消息仅出现一次

### 场景 15：MCP 工具卸载应同步到底层会话
- Given 已注册 MCP 工具并可在 `activeToolNames()` 与 `toolDescriptors()` 看到
- When 调用 `unregister(mcpToolNamed:)`
- Then MCP 工具应从 AgentSession 与底层 `SKILanguageModelSession` 同步移除
- And `activeToolNames()` 与 `toolDescriptors()` 不再包含该工具

### 场景 16：取消活动 prompt 后 pending 失败历史可观测
- Given 会话存在活动 prompt，且已排队 followUp/steer pending 项
- When 调用 `cancelActivePrompt()`
- Then 活动 prompt 与 awaiting followUp continuation 返回取消错误
- And `pendingMessages(includeResolved: true)` 中应包含这些 pending 项的 `failed` 状态记录

### 场景 17：resolved pending 历史容量上限与裁剪顺序
- Given 会话在取消路径下累计超过 20 条 pending failed 历史
- When 调用 `pendingMessages(includeResolved: true)`
- Then 仅保留最近 20 条历史记录
- And 早于窗口的历史被从头部裁剪，保留项顺序不变

### 场景 18：includeResolved 时自定义预览长度一致生效
- Given 会话存在 resolved pending 历史且文本超过默认长度
- When 调用 `pendingMessages(maxLength: 10, includeResolved: true)`
- Then queued 与 resolved 两类项都应按相同截断规则输出预览
- And 截断结果为 10 字符前缀加 `...`

### 场景 19：空闲态 fire-and-forget 的 resolved/failed 历史一致性
- Given 当前会话没有进行中的 prompt
- When 调用 `followUp("...")` 且执行成功
- Then `pendingMessages(includeResolved: true)` 中包含该消息的 `resolved` 历史
- When 调用 `followUp("...")` 且上游执行失败
- Then `pendingMessages(includeResolved: true)` 中包含该消息的 `failed` 历史
- And 调用 `steer("...")` 时也应满足同样的 `resolved/failed` 历史一致性

### 场景 20：从非法用户 entryIndex 分叉应返回业务错误
- Given 会话中已有用户消息历史
- When 调用 `fork(fromUserEntryIndex:)` 且索引不存在、不是用户消息或命中非 user entry
- Then 抛出 `SKIAgentSessionError.invalidForkEntryIndex(index)`
- And 不会创建新的 fork 会话

### 场景 21：fork 不应复制 pending 运行态
- Given 父会话存在 queued pending 或 resolved/failed pending 历史
- When 调用 `fork()`
- Then 子会话仅复制 transcript 快照
- And 子会话的 pending 队列与 resolved/failed 历史均为空

### 场景 22：fork 后工具注册变更应双向隔离
- Given 父会话已注册工具并创建了 fork 子会话
- When 父会话执行 `unregister(toolNamed:)`
- Then 子会话的工具清单与 active 工具不受影响
- When 子会话执行 `unregister(toolNamed:)`
- Then 父会话的工具清单与 active 工具不受影响

## 非目标
- 不实现预算控制
- 不实现持久化存储层（仅内存会话）
- 不实现多并发 prompt 执行
