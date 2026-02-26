# Codex ACP Runbook

## 1. 前置条件

1. 已安装 `codex` CLI，并完成登录。
2. 已安装 Node/npm（可用 `npx`）。
3. 当前仓库可执行 `swift run ski`。

## 2. 参考仓

- `references/openai-codex`
- `references/codex-acp`

## 3. 可执行性检查

```bash
codex --version
npx -y @zed-industries/codex-acp --help
```

## 4. 最小链路联调命令

```bash
swift run ski acp client connect \
  --transport stdio \
  --cmd npx \
  --args=-y \
  --args=@zed-industries/codex-acp \
  --cwd "$PWD" \
  --prompt "hello" \
  --json
```

预期：出现多条 `session_update`，最终输出一条 `prompt_result`。

## 5. 稳定性烟测

```bash
./scripts/codex_acp_smoke.sh 3
```

预期：输出 `success=3/3`。

说明：脚本会将每次运行的 stdout/stderr 写入 `/tmp/codex_acp_smoke_*.jsonl|*.err` 便于排障。

## 6. 常见问题

### 5.1 `session/new` 超时或解析错误

症状：日志出现 Rust 侧解析错误，类似 `expected a borrowed string`，并且请求超时。

处理：
1. 确认当前代码包含 JSON-RPC 编码修复（不转义 `/`）。
2. 运行：
   `swift test --filter JSONRPCCodecTests`
3. 重新执行最小链路联调命令。

### 5.2 MCP 相关噪声日志

症状：出现 `rmcp::transport::worker ... IncompleteMessage`。

说明：通常来自 Codex 侧配置的 MCP server 不可达，可能不影响本次最小链路成功。

处理：
1. 先看是否已拿到 `prompt_result`。
2. 若未成功，再排查 Codex 本地 MCP 配置与目标服务可达性。

### 5.3 登录态失效

症状：上游返回鉴权失败。

处理：
1. 重新执行 `codex` 登录流程。
2. 复跑最小链路命令。

### 5.4 `--session-id` 在 stdio 复用失败

症状：第二次执行 `connect --transport stdio --session-id <old>` 返回 `Resource not found`。

说明：`connect` 每次都会启动一个新的 `codex-acp` 进程；`sessionId` 通常只在该进程生命周期内有效。

处理：
1. 使用 `session/new` 新建会话（默认行为）。
2. 若需要跨请求复用同一会话，改为长连接模式（当前 `connect` 命令不是该模式）。

### 5.5 `--permission-decision deny` 与 allow 行为无明显差异

症状：某些 prompt 下 deny 仍可得到正常执行结果。

说明：`codex-acp` 侧并非所有执行路径都通过 ACP `request_permission` 回调；该参数只影响收到权限请求时客户端返回策略。

处理：
1. 先以 `prompt_result` 成功作为主验收标准。
2. 如需严格权限联调，需要构造 `codex-acp` 必经 `request_permission` 的场景再验证。

## 7. 回归命令

```bash
swift test --filter JSONRPCCodecTests
swift test --filter SKIToolShellTests --filter SKICLIProcessTests.testClientConnectViaStdioServeProcessSucceeds
```
