# Token Usage Tracking Spec

## 背景

当前 `SKIntelligence` 已可解析 OpenAI 兼容响应中的 `usage`，但缺少会话级统一累计与查询能力，导致上层无法稳定追踪 token 消耗。

## 目标

1. 提供会话级 token 统计（`prompt/completion/total/reasoning`）。
2. 覆盖同步 `respond` 与流式 `streamResponse` 两条链路。
3. 暴露聚合查询接口，供上层按需拉取。

## 非目标

1. 不做金额换算与预算控制。
2. 不做跨重启持久化恢复。
3. 不扩展外部 telemetry 协议。

## 公共接口

1. 新增 `SKITokenUsageSnapshot`：
   - `promptTokens`
   - `completionTokens`
   - `totalTokens`
   - `reasoningTokens`
   - `requestsCount`
   - `updatedAt`
2. `SKILanguageModelSession` 新增：
   - `tokenUsageSnapshot()`
   - `resetTokenUsage()`
3. `SKIAgentSession.SessionStats` 新增：
   - `tokenUsage: SKITokenUsageSnapshot`

## BDD 验收场景

1. 单次非流式响应返回 usage 时：
   - 查询快照应与 usage 对齐，`requestsCount = 1`。
2. 工具调用触发多轮 non-stream 响应时：
   - 快照应为多轮 usage 之和，不重复累计。
3. 流式响应存在最终 usage chunk 时：
   - 消费完整流后，快照应正确累计。
4. provider 未返回 usage 时：
   - 快照保持 0，不抛错。
5. 调用 `resetTokenUsage()` 后：
   - 统计归零，后续可重新累计。

## 兼容性

1. 仅新增字段/方法，不改现有 API 语义。
2. 旧调用方即使不读取新字段，行为保持不变。
