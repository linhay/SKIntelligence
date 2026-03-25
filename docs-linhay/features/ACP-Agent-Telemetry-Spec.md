# ACP Agent Telemetry 规格（v1）

## 目标

在不修改 ACP 标准方法语义的前提下，为 `ACPAgentService` 增加可选 telemetry 发射能力，覆盖 session 与 prompt 生命周期关键节点，便于后续观测、统计与问题回放。

## 协议边界（必须严格区分）

| 项目 | 归属 | 约束 |
| --- | --- | --- |
| `session/new`、`session/prompt`、`session/update` 等 JSON-RPC 方法 | ACP 协议域 | 必须遵循 ACP schema，不可夹带 telemetry 字段 |
| `ACPAgentTelemetryEvent`、`telemetrySink` | 非协议扩展域（实现层） | 仅在本地进程内使用，不参与协议编码与网络传输 |

边界原则：
- 不新增 ACP method，不修改 ACP response/result 结构。
- telemetry 关闭（sink=nil）时，协议行为与历史版本完全一致。
- telemetry 仅用于观测，不作为业务语义分支判断依据。

## 必要性说明

引入 telemetry 的必要性是补齐“协议外但工程必需”的可观测能力：
- ACP 标准消息不覆盖重试原因、权限拒绝原因、内部失败阶段等实现细节。
- 这些信息若写入标准协议会增加兼容风险；放在扩展域可避免污染协议面。
- 运维侧需要稳定事件流做统计、告警与回放，单靠文本日志不可控。

## 范围

- In Scope
  - `ACPAgentService` 增加可选 `telemetrySink` 注入。
  - 新增 `ACPAgentTelemetryEvent` 数据模型。
  - 发射 session/prompt/retry 关键生命周期事件。
  - 增加针对 telemetry 的单测。
  - 补齐 `execution_state_update` / `retry_update` golden fixtures。
- Out of Scope
  - 不新增 ACP JSON-RPC 方法。
  - 不引入预算控制或成本统计。
  - 不改变现有 `session/update` 协议语义。

## BDD 场景

1. Given 创建了 `ACPAgentService` 且注入 `telemetrySink`
   When 调用 `session/new`
   Then sink 应收到 `session_new` 事件。

2. Given 已创建 session 且注入 `telemetrySink`
   When 调用 `session/prompt` 并成功完成
   Then sink 应按生命周期收到 `prompt_requested`、`prompt_started`、`prompt_completed`。

3. Given prompt 配置了重试且第一次失败后成功
   When 进入重试
   Then sink 应收到 `prompt_retry`，且包含 `attempt/maxAttempts/reason`。

## 验收标准

- telemetry 为可选能力，不注入 sink 时行为与当前一致。
- telemetry 事件字段至少包含：`name`、`sessionId?`、`requestId?`、`attributes`、`timestamp`。
- 现有 ACP 回归测试全部通过。
- golden fixture 覆盖 `execution_state_update` 与 `retry_update` 的 decode/encode roundtrip。

## 风险

- telemetry 名称和属性若缺少命名规范，后续易产生指标口径分裂。
- telemetry 属于非标准扩展，需明确文档标记“非 ACP 规范字段/能力”。
