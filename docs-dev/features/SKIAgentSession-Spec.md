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

## 非目标
- 不实现预算控制
- 不实现持久化存储层（仅内存会话）
- 不实现多并发 prompt 执行
