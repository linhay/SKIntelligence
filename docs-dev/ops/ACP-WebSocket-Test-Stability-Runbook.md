# ACP WebSocket 测试稳定性 Runbook（2026-02-13）

## 目标

降低 `Address already in use`、资源未清理导致的 WebSocket 集成测试波动，保证 ACP 回归在并行执行下稳定。

## 关键措施

1. 使用统一测试基础设施 `ACPWebSocketTestHarness`：
   - `makeServerTransport(...)`：端口占用时自动重试分配。
   - `makeServerTransport(onFixedPort:...)`：固定端口重启场景（reconnect）重试绑定。
2. 统一将高风险 WebSocket 用例切换到 harness 分配端口：
   - `ACPWebSocketRoundtripTests`
   - `ACPWebSocketPermissionRoundtripTests`
   - `ACPWebSocketMultiClientTests`
   - `ACPTransportConsistencyTests`
   - `ACPWebSocketReconnectTests`
3. 保持测试结束清理：
   - 取消 server loop task
   - 关闭 client transport
   - 关闭 server transport

## 标准回归命令

```bash
swift test --filter ACPWebSocketTestHarnessTests \
  --filter ACPWebSocketRoundtripTests \
  --filter ACPWebSocketPermissionRoundtripTests \
  --filter ACPWebSocketMultiClientTests \
  --filter ACPTransportConsistencyTests
```

全量 ACP 回归：

```bash
swift test --filter ACP --parallel
```

## 故障排查

1. 若仍出现端口占用：
   - 先重跑失败用例；
   - 若持续失败，检查是否有遗留 `ski acp serve` 或测试进程未退出。
2. 若 reconnect 用例波动：
   - 保留固定端口重试；
   - 避免减小 server 重启后的等待窗口（目前 120ms + heartbeat 窗口）。
3. 若 CI 并发度提高后出现抖动：
   - 优先增加 harness `attempts`，不要回退到固定端口。
