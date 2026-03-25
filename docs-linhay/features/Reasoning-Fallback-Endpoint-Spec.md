# Reasoning Fallback Endpoint Spec

## 背景

`OpenAIClient` 过去以分散字段（`url/token/model/headerFields`）描述请求配置。单端点故障时，切换行为无法保证整组配置一致。

## 目标

1. 支持以 `EndpointProfile` 数组描述多端点配置。
2. 当前 profile 失败且属于可重试错误时，按数组顺序切换到下一个 profile。
3. 保持现有重试语义兼容（`RetryConfiguration` 仍生效）。

## 非目标

1. 不实现跨请求健康检查与熔断状态持久化。
2. 不引入新依赖或复杂负载均衡策略。

## API 设计

1. `OpenAIClient` 新增：
   - `EndpointProfile`（`url/token/model/headerFields`）
   - `profiles: [EndpointProfile]`
   - `profiles(_ values: [EndpointProfile]) -> OpenAIClient`
   - `addProfile(_ value: EndpointProfile) -> OpenAIClient`
2. 请求候选顺序：严格按 `profiles` 下标顺序尝试，不做主次区分。
3. 兼容层：
   - 旧 `.url/.token/.model` 与 `fallbackURLs` 保留但标记 `deprecated`，内部映射到 `profiles`。

## 行为规则

1. 当请求失败且错误可重试时，下一次尝试切换到下一个 profile。
2. 若候选端点全部失败，则按既有语义返回原始错误或 `retryExhausted`。
3. 流式请求在当前 profile 连接失败且尚未收到任何 chunk 时，允许切换到下一个 profile 重连。
4. 认证优先级：若 `headerFields` 已显式包含 `Authorization`，优先使用该值；否则才使用 `token` 自动补 Bearer。
5. `profiles` 为空时立即返回配置错误（`invalidArguments`）。

## BDD 验收场景

1. Given `profiles[0]` 返回 503，`profiles[1]` 返回 200
   - When 调用 `respond`
   - Then 最终成功，且请求顺序为 `profiles[0] -> profiles[1]`。
2. Given 仅一个 profile 且返回 503
   - When 调用 `respond`
   - Then 返回可重试失败，不会伪造成功。
3. Given 同时配置 `token` 与 `headerFields.Authorization`
   - When 调用 `respond`
   - Then 使用 header 中的 Authorization。
4. Given `profiles = []`
   - When 调用 `respond/streamingRespond`
   - Then 立即返回配置错误。
