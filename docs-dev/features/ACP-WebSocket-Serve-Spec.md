# ACP WebSocket Serve 规格（v1）

## 背景
- CLI 已支持 `ski acp serve --transport stdio` 与 `ski acp client connect --transport ws`。
- 现补齐本地 WebSocket 服务端传输，使 ACP agent 可直接通过 ws 暴露。

## 验收场景（BDD）
1. Given 启动 `ski acp serve --transport ws --listen 127.0.0.1:8900`
   When ACP 客户端通过 `ws://127.0.0.1:8900` 连接并执行 `initialize/session/new/prompt`
   Then 客户端收到 `session/update` 通知与 `session/prompt` 成功响应（`stopReason=end_turn`）。

2. Given 启动 `ski acp serve --transport stdio`
   When 客户端走 stdio 链路调用 ACP
   Then 既有行为与输出保持不变。

3. Given WebSocket 服务端已启动但尚无客户端连接
   When 服务端尝试发送消息
   Then 返回未连接错误，不发生崩溃。

4. Given WebSocket 客户端已启用重连策略（`reconnectAttempts > 0`）
   When 临时网络错误导致一次收发失败
   Then 客户端按退避延迟自动重连并继续后续请求。

5. Given 服务端或客户端设置 `maxInFlightSends`
   When 瞬时并发发送超过阈值
   Then 发送端触发背压等待，不出现无限制内存增长。

6. Given JSON-RPC line framer 收到大体积单行消息（>= 512KB）
   When 进行 encode/decode 回环
   Then 消息内容一致，不发生 envelope 误判。

7. Given 同一 session 已有正在运行的 `session/prompt`
   When 客户端并发发送第二个 `session/prompt`
   Then agent 返回 `invalid params (-32602)`，防止 session 级竞态。

8. Given 客户端接收链路出现乱序、重复 `response` 或未知 `id` 的噪声包
   When 仍有有效请求在途
   Then 客户端按 `id` 精确匹配 pending 请求，忽略噪声包，不影响后续请求。

9. Given 客户端高并发发送 `session/new`（>=40）
   When 响应乱序返回
   Then 所有请求都应在超时前完成，且 pending/timeout 内部状态清空为 0。

10. Given 客户端存在 in-flight 请求
    When 调用 `client.close()`
    Then 所有 in-flight 请求都以 EOF 失败返回，且 pending/timeout 状态清空为 0。

11. Given `client.close()` 与 request timeout 可能并发发生
    When close 先发生
    Then 结果优先收敛为 EOF；
    When timeout 先发生
    Then 返回 `requestTimeout`，语义保持单一且可预测。

12. Given 客户端已经关闭
    When 再次调用 `client.close()`
    Then 应保持幂等，无额外副作用；
    When 继续发起 API 请求
    Then 返回 `notConnected`。

13. Given `session/prompt` 生命周期处于取消或超时路径
    When 处理完成
    Then 不应发送 `session/update` 通知；
    Given 正常路径
    Then `session/update` 先于 prompt 结果返回。

14. Given 客户端并发发送请求（>=200）
    When 传输层允许乱序返回
    Then request id 必须全局唯一且连续分配，不出现重复或跳号。

15. Given 客户端长时顺序运行（>=1000 次调用）
    When 全部请求完成
    Then pending 与 timeoutTasks 内部状态应为 0，避免状态泄漏。

16. Given 发送背压 gate 已满且存在等待中的发送任务
    When 某个等待任务在获取 permit 前被取消
    Then 该任务不应占用发送配额，后续有效发送任务可继续获取 permit（不死锁）。

17. Given WebSocket 客户端传输注入可脚本化连接工厂（不依赖真实网络）
    When 首次 `send` 或 `receive` 失败并触发 retry
    Then 客户端应执行重连并在后续连接上恢复请求/响应路径，作为默认回归测试（非 live-only）。

18. Given 客户端存在高并发请求（>=200）且在随机时机触发 `client.close()`
    When 请求结果汇总
    Then 结果仅允许 success / EOF / notConnected / requestTimeout，且 pending/timeout 状态最终清零。

19. Given ACP WebSocket 服务端同一端口有两个客户端同时连接
    When 两个客户端分别发起 `initialize/session/new/prompt`
    Then 两个客户端都能独立收到各自请求的响应，不互相串线。

20. Given 多客户端并发连接且服务端收到来自不同连接的 request
    When 服务端发送 `response`
    Then 必须按 `response.id` 回写到原始请求来源连接，不能发到“最后连接”的客户端。

21. Given 多客户端同时在线
    When 服务端发送 `session/update` 等 notification
    Then notification 应广播到所有在线连接（至少确保不会遗漏活跃连接）。

22. Given client 已连接并收到 agent 发起的 `session/request_permission` request
    When client 注册了 permission handler
    Then client 应回写 JSON-RPC `response(result)` 到同一 `id`，用于 permission 决策闭环。

23. Given `initialize.protocolVersion` 非当前支持版本（v1）
    When agent 处理 initialize
    Then 返回 `invalid params (-32602)`，避免静默降级导致协议歧义。

24. Given agent `capabilities.loadSession = false`
    When client 调用 `session/load`
    Then 返回 `method not found (-32601)`，与 capability 协商结果一致。

25. Given agent 在执行 `session/prompt` 前启用了 permission requester
    When permission 结果为 `allow=false`
    Then prompt 应短路返回 `stopReason=cancelled`，且不发送 `session/update`、不触发模型调用。

26. Given `acp serve` 通过 websocket 对接 client 且 agent 触发 `session/request_permission`
    When client permission handler 返回 `allow=true`
    Then permission 往返应成功闭环，prompt 继续执行并返回 `end_turn`。

27. Given `acp serve` 触发 permission request 但链路中断/关闭
    When permission bridge 清理 pending 请求
    Then 所有挂起 permission 请求应快速失败，不残留 pending 状态。

28. Given `acp serve` 配置 `--permission-mode permissive`
    When permission bridge 出现 timeout/传输错误
    Then 允许 fallback 放行 prompt（便于与未实现 permission 的旧 client 兼容）。

29. Given `acp serve` 配置 `--permission-mode required`
    When permission bridge 出错或 client 拒绝
    Then prompt 不应继续执行，保持严格权限语义。

30. Given agent 在 initialize 响应中声明 `authMethods`
    When client 调用 `authenticate` 且 methodId 合法
    Then agent 返回成功响应；当 methodId 非法时返回 `invalid params (-32602)`。

31. Given agent 支持会话模式与配置项
    When client 调用 `session/set_mode`
    Then agent 更新当前模式并通过 `session/update(current_mode_update)` 通知客户端。

32. Given agent 支持会话配置项
    When client 调用 `session/set_config_option`
    Then agent 更新配置并通过 `session/update(config_option_update)` 通知客户端。

33. Given client 在 initialize 时声明 `fs.readTextFile=true`
    When agent 发起 `fs/read_text_file`
    Then client 按请求路径/行号/限制返回文本内容；参数错误返回 `invalid params`。

34. Given client 在 initialize 时声明 `fs.writeTextFile=true`
    When agent 发起 `fs/write_text_file`
    Then client 成功写入并返回响应；写入失败返回 `internal error`。

35. Given client 在 initialize 时声明 `terminal=true`
    When agent 依次调用 `terminal/create/output/wait_for_exit/release`
    Then client 返回终端生命周期结果并可在 `session/update` 中引用 `terminalId`。

36. Given agent 调用 `terminal/kill` 后再调用 `terminal/output`
    When 终端已被终止但未 release
    Then client 仍可返回最终输出与退出码，直到 `terminal/release` 后 `terminalId` 失效。

37. Given agent 发起 `session/request_permission`
    When client 响应 permission
    Then response 必须使用 `outcome` 结构（`selected.optionId` 或 `cancelled`），不再使用 `allow/message` 旧结构。

38. Given agent 调用 `session/new`
    When session 创建成功
    Then response 应包含 `sessionId`，并可携带 `modes` 与 `configOptions` 初始状态。

39. Given agent 调用 `session/load`
    When session 加载成功
    Then response 应返回对象结构（可为空对象），并可携带 `modes` 与 `configOptions`。

40. Given agent 调用 `terminal/output`
    When 终端有输出
    Then response 必须包含 `output`、`truncated`，且退出信息通过 `exitStatus{exitCode,signal}` 返回。

41. Given agent 调用 `terminal/wait_for_exit`
    When 终端已退出
    Then response 使用 `exitCode/signal` 结构，兼容正常退出与信号终止两类场景。

42. Given agent 处理一次成功的 `session/prompt`
    When 进入工具调用可观测阶段
    Then 应按顺序发送 `session/update(tool_call)` -> `session/update(tool_call_update)` -> `session/update(agent_message_chunk)`。

43. Given agent 处理一次成功的 `session/prompt`
    When 进入执行前的计划与命令发现阶段
    Then 应先发送 `session/update(available_commands_update)` 与 `session/update(plan)`，再进入 tool call 生命周期更新。

44. Given agent 发送 `session/update(tool_call|tool_call_update)`
    When client 解析工具调用生命周期
    Then payload 应支持 ACP 工具调用标准字段：`kind/status/locations/content/rawInput/rawOutput`，且 `tool_call_update` 允许仅发送增量字段（如仅 `status`）。

45. Given client/agent 交换 `prompt` 与 `session/update(*_message_chunk)`
    When content block 不是纯文本
    Then payload 应支持 ACP `ContentBlock` 常见字段（至少 `image`、`audio`、`resource_link`）并保持与 text 兼容。

46. Given client/agent 交换 `session/update`
    When `sessionUpdate` 为具体判别值（如 `plan` / `tool_call` / `current_mode_update`）
    Then payload 必须按判别值携带对应必需字段，不允许仅靠“可选大包字段”弱约束。

47. Given 维护 ACP 业务域编解码兼容性
    When 执行模型回归
    Then 必须包含基于 golden JSON fixture 的 decode->encode 双向一致性测试（至少覆盖 `tool_call_update` 与 `agent_message_chunk`）。

48. Given ACP client 分别通过 `stdio` 与 `ws` 连接同一类 agent 行为
    When 执行 `initialize/session/new/prompt`
    Then `session/update` 关键 kind 序列与终止语义应保持一致，避免传输层导致业务域偏差。

49. Given agent 声明支持 `session/set_model`（unstable 能力）
    When client 调用 `session/set_model(sessionId, modelId)`
    Then agent 应更新会话当前模型并返回成功；当 `modelId` 非可选模型时返回 `invalid params (-32602)`。

50. Given agent 声明支持 `session/list`（unstable 能力）
    When client 调用 `session/list`
    Then response 应返回 `sessions[]`，每项至少包含 `sessionId` 与 `cwd`，可选 `title/updatedAt`。

51. Given agent 声明支持 `session/resume`（unstable 能力）
    When client 调用 `session/resume(sessionId, cwd, mcpServers)`
    Then response 语义应等价于“恢复会话状态不回放历史”，至少可返回 `modes/configOptions`，并允许附带 `models`。

52. Given agent 声明支持 `session/fork`（unstable 能力）
    When client 调用 `session/fork(sessionId, cwd, mcpServers)`
    Then agent 应返回一个新的 `sessionId`，且新会话继承源会话的模式/模型/配置状态。

53. Given agent 声明支持 `session/list`（unstable 能力）且会话数量超过单页上限
    When client 首次调用 `session/list(cursor=nil)` 并继续用 `nextCursor` 拉取后续页
    Then agent 应返回真实分页结果：每页返回固定批次数据，且在最后一页返回 `nextCursor=null`。

54. Given client 使用无效或过期的 `session/list.cursor`
    When agent 处理 `session/list`
    Then 返回 `invalid params (-32602)`，并明确 cursor 不可用，避免静默回退到第一页。

55. Given 维护 ACP golden fixture 回归
    When 执行 fixture decode->encode 一致性验证
    Then 至少覆盖 `available_commands_update` 与 `current_mode_update`，防止 session update 判别联合回归。

56. Given agent 声明支持 `session/delete`（能力位 `sessionCapabilities.delete`）
    When client 调用 `session/delete(sessionId)`
    Then 删除应幂等成功（不存在/已删除也成功），且后续 `session/list` 不再返回该会话。

57. Given agent 未声明 `sessionCapabilities.delete`
    When client 调用 `session/delete`
    Then agent 返回 `method not found (-32601)`，与 capability 协商一致。

58. Given 会话元数据发生变化（例如首次 prompt 后自动生成标题）
    When agent 发送 `session/update`
    Then 应发送 `sessionUpdate=session_info_update`，并携带可选 `title/updatedAt` 字段供 client 实时刷新会话列表。

59. Given client 发送协议级通知 `$/cancel_request`（携带运行中 requestId）
    When 该 request 对应 `session/prompt` 正在执行
    Then agent 应取消对应 prompt，且不影响其它 request。

60. Given agent 声明 `authCapabilities.logout`
    When client 调用 `logout`
    Then agent 应返回成功并清理认证态相关会话上下文。

61. Given client 发送 `$/cancel_request` 且命中运行中 request
    When agent 对应请求被协议级取消
    Then 原请求应返回 JSON-RPC 错误码 `-32800`（request cancelled）。

62. Given 维护 ACP 规范对齐
    When 执行协议一致性守卫测试
    Then 方法集必须与官方 `meta.json/meta.unstable.json` 快照一致，且项目扩展仅允许 `logout` 与 `session/delete`。

63. Given 项目需要对标 pi 的会话可维护能力（非 ACP stable/unstable 标准方法）
    When client 调用扩展方法 `session/export(sessionId, format=jsonl)`
    Then agent 返回完整 JSONL 文本（包含 header + message lines），并明确该能力属于“扩展域”。

64. Given 会话由 `session/fork` 派生
    When client 调用 `session/list`
    Then 对应 fork 会话条目应包含 `parentSessionId` 元数据，便于客户端构建会话谱系视图。

63. Given 测试环境并发执行多个 WebSocket 用例
    When 某个候选端口已被占用（`Address already in use`）
    Then 测试基础设施应自动重试并分配新端口，避免因固定端口冲突导致非业务失败。

64. Given WebSocket 集成测试结束（成功或失败）
    When 执行资源清理
    Then client/server transport 与 server loop 必须被关闭/取消，避免句柄泄漏影响后续测试。

63. Given agent 开启 prompt 执行状态更新能力
    When client 调用 `session/prompt`
    Then agent 应通过 `session/update(execution_state_update)` 按顺序发送 `queued -> running -> completed|cancelled|timed_out|failed` 状态。

64. Given agent 未开启 prompt 执行状态更新能力（默认）
    When client 调用 `session/prompt`
    Then `session/update` 行为保持兼容，不额外发送 `execution_state_update`。

65. Given agent 配置了 `promptExecution.maxRetries > 0`
    When `session/prompt` 首次执行遇到可恢复错误
    Then agent 应继续重试并发送 `session/update(retry_update)`，最终成功时返回 `end_turn`。

66. Given agent 配置了重试但所有尝试均失败
    When `session/prompt` 重试耗尽
    Then agent 返回错误响应，并发送 `execution_state_update(state=failed)`。

63. Given agent 启用 Permission Policy 且 mode=`allow`
    When 执行 `session/prompt` 触发权限决策
    Then agent 直接返回放行结果（`allow_once`），不向 client 发起 `session/request_permission`。

64. Given agent 启用 Permission Policy 且 mode=`deny`
    When 执行 `session/prompt` 触发权限决策
    Then agent 直接拒绝（`cancelled`），不向 client 发起 `session/request_permission`。

65. Given agent 启用 Permission Policy 且 mode=`ask`
    When client 返回 `allow_always` 或 `reject_always`
    Then 同一 session 内相同工具调用后续命中记忆，不再重复发起 `session/request_permission`。

66. Given Permission Policy 已记录会话级决策记忆
    When 执行 `session/delete` 或 `logout`
    Then 对应 session 的权限记忆必须清理，后续请求不应命中旧决策。

67. Given client 调用兼容扩展方法 `session/stop(sessionId)`
    When 目标 session 存在运行中的 `session/prompt`
    Then prompt 应被终止并返回 `stopReason=cancelled`，且 stdio/ws 语义一致。

## 非目标
- 不引入鉴权与远程公网部署策略（当前仅本地模式）。
