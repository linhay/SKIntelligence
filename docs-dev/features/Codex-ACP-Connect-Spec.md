# Codex ACP Connect Spec

## 背景

当前仓库已具备 ACP Client（stdio / ws）。本规格定义通过 `codex-acp` 适配器连接 Codex 的最小可用链路验收。

参考：
- https://github.com/zed-industries/codex-acp
- https://github.com/openai/codex
- https://agentclientprotocol.com/get-started/clients

## 目标

在不改 ACP 协议模型的前提下，验证并固化：
1. `initialize` 成功
2. `session/new` 成功
3. `session/prompt` 成功并返回 `prompt_result`

## 非目标

1. 不覆盖 Codex 全能力矩阵（permission/fs/terminal 全域）。
2. 不引入新 ACP 方法。
3. 不做 TUI 改造。

## BDD 场景

### 场景 1：最小链路成功

- Given 本机存在 `codex` 且登录态可用
- And 可执行 `npx -y @zed-industries/codex-acp --help`
- When 执行
  `swift run ski acp client connect --transport stdio --cmd npx --args=-y --args=@zed-industries/codex-acp --cwd <有效目录> --prompt "hello" --json`
- Then 客户端应完成 `initialize + session/new + session/prompt`
- And 输出 `prompt_result`（含 `stopReason`）

### 场景 2：适配器缺失

- Given 运行环境无 `npx` 或无法获取 `@zed-industries/codex-acp`
- When 执行同一命令
- Then 返回明确可诊断错误（可执行/依赖缺失）

### 场景 3：鉴权不可用

- Given `codex` 登录态失效
- When 执行同一命令
- Then 返回上游错误并保持 CLI 退出码语义（upstream failure）

## 验收标准

1. 最小链路命令至少一次返回 `prompt_result`。
2. 不再出现 `session/new` 解析失败（`expected a borrowed string`）。
3. 相关 JSON-RPC 编码测试通过。

## 设计约束

1. 对外协议保持 ACP 标准方法名。
2. JSON-RPC 编码必须避免将 `method` 中 `/` 编码为 `\/`，以兼容 Rust 端借用字符串反序列化路径。
3. `references/` 仅做长期参考，不纳入提交。
