# SKIntelligence 2.0.2

发布日期：2026-03-05

## TL;DR

`2.0.2` 是 `2.0.0` 的稳定性补丁版本，重点修复 `WS + MLX` 控制帧导致的连接中断问题，
并将客户端连接默认超时提升到 5 分钟，减少 MLX 首次加载阶段误报超时。

## 主要变化

- 修复 WebSocket server 对控制帧处理：
  - 忽略 `ping/pong/close` 等非业务 opcode；
  - 不再因 `Unsupported websocket frame opcode` 中断 receive loop。
- 新增对应回归测试：
  - 心跳控制帧 + 慢响应场景；
  - client close 控制帧后 server 存活场景。
- 调整默认请求超时：
  - `acp client connect` / `connect-stdio` / `connect-ws` 默认 `--request-timeout-ms` 提升为 `300000`；
  - `ski tui` 与默认聊天入口同步为 `300000`；
  - `stop` 系列命令保持 `60000`。
- CLI 体验改进：
  - `ski` 默认进入聊天页（TTY）；
  - `/` 作为聊天页连接与配置入口。

## 验证

- 脚本回归：`RUN_CODEX_PROBES=0 ./scripts/acp_regression_suite.sh`（必跑 5/5 PASS）
- 门禁回归：`./scripts/test_acp_gate.sh`（302 通过，1 跳过，0 失败）
- 冒烟：
  - `WS + MLX`（默认参数）`prompt_result:end_turn`
  - `stdio + MLX`（默认参数）`prompt_result:end_turn`
