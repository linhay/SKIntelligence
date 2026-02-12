# ACP Runtime 与 Session 持久化规格（v1）

## 目标

在现有 ACP 协议实现基础上补齐三项核心能力：
1. 客户端 Runtime 抽象（FS Runtime / Terminal Runtime）
2. Runtime 与 ACPClientService 的标准接线
3. SKIAgentSession 的 JSONL 持久化入口（可恢复）

## 范围

- In Scope
  - 新增可复用的 `ACPFilesystemRuntime` 抽象。
  - 新增可复用的 `ACPTerminalRuntime` 抽象。
  - 提供默认本地实现：本地文件系统 + `Process` 终端运行时。
  - 提供 `ACPClientService` 统一安装 runtime 的接口。
  - `SKIAgentSession` 提供 JSONL 持久化启用接口。
- Out of Scope
  - 不引入 TUI。
  - 不引入预算/成本控制。
  - 不改变现有 ACP JSON-RPC 方法语义。

## BDD 场景

1. Given ACP client 收到 `fs/read_text_file` 请求
   When 安装了 `ACPFilesystemRuntime`
   Then `ACPClientService` 应调用 runtime 并返回 `ACPReadTextFileResult`。

2. Given ACP client 收到 `fs/write_text_file` 请求
   When 安装了 `ACPFilesystemRuntime`
   Then `ACPClientService` 应调用 runtime 并返回 `ACPWriteTextFileResult`。

3. Given ACP client 收到 terminal 域请求（create/output/wait_for_exit/kill/release）
   When 安装了 `ACPTerminalRuntime`
   Then `ACPClientService` 应调用 runtime 并按请求返回对应结果。

4. Given 本地文件系统 runtime 启用 rooted policy
   When 访问 root 目录外路径
   Then 应返回 permission denied 错误。

5. Given `SKIAgentSession` 启用了 JSONL 持久化
   When 会话产生消息并新建会话重新启用同一 JSONL 文件
   Then 新会话应能恢复历史 transcript。

## 验收标准

- 新增 Runtime 抽象类型与默认实现可直接在 CLI/集成中复用。
- 新增 `ACPClientService` runtime 安装接口后，现有 handler 机制保持兼容。
- 新增 `SKIAgentSession` 持久化 API 后，现有 prompt/fork/resume/cancel 行为不回归。
- 新增测试覆盖：
  - Runtime 单测
  - Runtime + ACPClientService 集成测试
  - SKIAgentSession JSONL 持久化恢复测试

## 风险

- 终端子进程在 CI 环境可能存在时序波动，需要使用容忍等待与稳定断言。
- rooted 路径策略需明确统一比较规则，避免软链接与相对路径误判。
