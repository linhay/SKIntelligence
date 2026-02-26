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

### 4.1 单连接多轮 prompt（推荐用于会话连续性联调）

```bash
swift run ski acp client connect \
  --transport stdio \
  --cmd npx \
  --args=-y \
  --args=@zed-industries/codex-acp \
  --cwd "$PWD" \
  --prompt "first turn" \
  --prompt "second turn" \
  --json
```

预期：输出两条 `prompt_result`，且 `sessionId` 相同。

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
2. 若需要会话连续性，优先在一次 `connect` 中重复使用多个 `--prompt`（单连接多轮）。
3. 可用 `./scripts/acp_stdio_session_reuse_probe.sh` 验证该失败边界（预期 exit=4）。

补充（本地 ws）：
- 在同一个 `acp serve --transport ws` 进程生命周期内，`--session-id` 可跨连接复用。
- 可用 `./scripts/acp_ws_session_reuse_probe.sh` 验证。
- 若传入不存在的 `--session-id`，预期 upstream failure（exit=4）。

### 5.5 `--permission-decision deny` 与 allow 行为无明显差异

症状：某些 prompt 下 deny 仍可得到正常执行结果。

说明：`codex-acp` 侧并非所有执行路径都通过 ACP `request_permission` 回调；该参数只影响收到权限请求时客户端返回策略。  
客户端 stderr 现会输出：`[SKI] ACP client permission requests=<N>`，可直接判断该轮是否触发 ACP 权限请求。

处理：
1. 先以 `prompt_result` 成功作为主验收标准。
2. 若 `N=0`，说明 deny/allow 差异不会生效。
3. 如需严格权限联调，需要构造 `codex-acp` 必经 `request_permission` 的场景再验证。

### 5.6 本地 `ski acp serve --transport stdio` 的多轮差异

症状：在 `connect-stdio --cmd ski --args acp --args serve --args=--transport --args=stdio` 下，第二轮 prompt 可能超时。

说明：这是当前本地 stdio serve 路径的已知限制；同样的多轮流程在 `codex-acp` 与本地 ws serve 路径可正常通过。

处理：
1. 对多轮连续性联调，优先使用 `codex-acp`（stdio）或本地 `serve --transport ws`。
2. 本地 stdio serve 继续保留单轮验收。

## 7. 回归命令

```bash
swift test --filter JSONRPCCodecTests
swift test --filter SKIToolShellTests --filter SKICLIProcessTests.testClientConnectViaStdioServeProcessSucceeds
```

## 8. 权限矩阵联调（本地 ws）

```bash
./scripts/acp_ws_permission_matrix.sh
```

预期：
- `allow` 分支得到 `stopReason=end_turn`
- `deny` 分支得到 `stopReason=cancelled`

## 9. `codex-acp` 权限探针

```bash
./scripts/codex_acp_permission_probe.sh
```

输出示例：
- `probe-allow permission_requests=0 stop_reason=end_turn`
- `probe-deny permission_requests=0 stop_reason=end_turn`

含义：
- `permission_requests=0` 表示该 prompt 路径未触发 ACP `session/request_permission`。

## 10. 一键回归套件

```bash
./scripts/acp_regression_suite.sh
```

默认覆盖：
1. `ws` 权限矩阵（allow/deny）
2. `ws` 跨连接 session 复用
3. `stdio` 跨连接 session 复用失败边界
4. `ws` `--session-ttl-ms=0` 立即过期边界（预期 `Session not found`, exit=4）
5. `ws` `--request-timeout-ms=0` 禁用超时边界（预期 `stopReason=end_turn`）

可选附加（需要 codex 环境）：
```bash
RUN_CODEX_PROBES=1 ./scripts/acp_regression_suite.sh
```

说明：
- `RUN_CODEX_PROBES=1` 会附加执行 `codex_acp_permission_probe.sh` 与 `codex_acp_multiturn_smoke.sh`。
- 两个 codex 可选阶段都带 1 次自动重试，降低瞬时波动导致的假失败。
- codex 阶段失败时会输出 `WARN` 但不阻断主套件 PASS/FAIL（主套件仅由前 5 个本地 ACP 阶段决定）。
- 可通过 `CODEX_ACP_TIMEOUT_MS` 调整 codex multi-turn 探针超时（默认 `60000`ms）。
- 可通过 `CODEX_PROBE_RETRIES` 调整 codex 可选探针重试次数（默认 `2`，即失败后再重试 1 次）。
- 可通过 `CODEX_PROBE_RETRY_DELAY_SECONDS` 设置 codex 可选探针重试间隔（默认 `2` 秒）。
- 可通过 `STRICT_CODEX_PROBES=1` 启用严格模式：codex 可选探针失败会让套件直接失败（默认 `0` 为仅告警继续）。
- 可通过 `ACP_PORT_BASE` 覆盖本地 ws 探针端口基线（默认 `18920`），用于并行执行多套回归避免端口冲突。
- 可通过 `ACP_SUITE_SUMMARY_JSON=/path/to/summary.json` 输出机器可读的回归汇总（包含每阶段 `status/exitCode`）。
- 汇总中包含 `startedAtUtc/finishedAtUtc/durationSeconds` 与 `config`（端口基线、重试参数、strict 开关）便于排障追踪。
- 每个 `stages[]` 项含 `durationSeconds` 与 `attempts`，可快速识别慢阶段和重试抖动阶段。
- 当 `RUN_CODEX_PROBES=0` 时，`codex_permission_probe`/`codex_multiturn_smoke` 会在 summary 中标记为 `status=skipped`（结构保持固定 7 段）。
- summary 文件采用原子写入（临时文件后 `mv`），避免 CI 读取到半写入内容。
- summary 顶层包含 `schemaVersion`（当前为 `1`），下游解析建议先校验版本再消费字段。
- `stages[]` 包含固定 `index`（1..7），便于前端/报表按稳定顺序展示。
- 顶层 `runId` 为单次套件执行唯一标识，可用于关联同轮的日志与 summary。
- 可通过 `ACP_SUITE_RUN_ID` 覆盖 `runId`（例如注入 CI job/build id）。
- 每个 stage 记录 `startedAtUtc/finishedAtUtc`，可与外部日志按时间戳精确对齐。
- 顶层包含 `gitHead` 与 `gitDirty`，用于把回归结果绑定到具体代码快照及工作区状态。

示例：
```bash
ACP_SUITE_SUMMARY_JSON=/tmp/acp_suite_summary.json ./scripts/acp_regression_suite.sh
cat /tmp/acp_suite_summary.json
```
