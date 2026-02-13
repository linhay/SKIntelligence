# ACP 协议域与扩展域边界总览（v1）

## 目标

统一约束 SKIntelligence 在 ACP 落地中的“协议能力”与“非协议扩展能力”，避免后续实现把本地扩展字段混入 ACP JSON-RPC payload。

## 边界原则

1. 协议域必须严格遵循 ACP schema（method 名、params/result 字段、session/update 判别联合）。
2. 扩展域只允许在本地实现层生效（in-process），不得进入网络传输 payload。
3. 扩展能力必须可关闭或可替换，不得影响协议兼容行为。

## 边界清单

| 能力 | 归属 | 说明 | 协议约束 |
| --- | --- | --- | --- |
| `ACPAgentService` 方法处理（`session/*`, `authenticate`, `logout`） | 协议域 | ACP method 编排 | 仅使用 ACP 定义字段 |
| `session/update` 业务事件 | 协议域 | 对外协议事件流 | 仅允许 schema 支持的 update kind 与字段 |
| `ACPAgentTelemetryEvent` / `telemetrySink` | 扩展域 | 本地观测事件 | 不得序列化进 ACP payload |
| `ACPFilesystemRuntime` / `ACPTerminalRuntime` | 扩展域 | client 侧本地 runtime 接口 | 不新增 ACP method |
| `ACPFilesystemAccessPolicy` / `ACPProcessTerminalRuntime.Policy` | 扩展域 | 本地访问控制策略 | 不写入 ACP params/result |
| `ACPPermissionPolicy` | 扩展域 | 本地权限决策策略 | 协议交互仅通过 `session/request_permission` |

## 必要性

- 协议稳定性：避免因扩展字段导致跨语言 SDK 互操作失败。
- 工程可观测：重试、超时、权限记忆等实现细节需要独立观测通道。
- 安全与治理：本地 policy/runtime 便于按部署环境定制，不破坏统一协议面。

## 验收

- 代码中扩展入口都有“Non-ACP extension”注释。
- 测试存在“扩展字段不进入协议载荷”的守卫用例。
- feature/dev 文档可直接检索到该边界规范。
