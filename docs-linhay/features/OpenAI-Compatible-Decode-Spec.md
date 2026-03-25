# OpenAI Compatible Chat Decode 兼容规格

## 目标

在不改变对外接口的前提下，提升 `ChatResponseBody` 对 OpenAI-compatible 响应变体的兼容性，避免单字段形态差异导致整包解码失败。

约束：

- 对外仅保留一套稳定业务模型（`ChatResponseBody`）。
- 兼容逻辑收敛在解码层（内部 Raw + normalize）。
- 调用方接口与调用方式保持不变。

## 非目标

- 不引入长期双轨调用或 fallback 分叉。
- 不引入 provider-specific 分支策略（本期先做通用兼容）。

## BDD 场景

1. Given `message.content` 是字符串或 `null`
   When 解码 `ChatResponseBody`
   Then 解码成功，语义与现有行为一致。

2. Given `message.content` 是 `[]` 或 `[{type,text}]`
   When 解码 `ChatResponseBody`
   Then 解码成功；数组文本片段按顺序合并为字符串；空数组不导致解码失败。

3. Given `tool_calls` 缺省、`null`、空数组、或包含部分坏项
   When 解码 `ChatResponseBody`
   Then 解码成功；坏项被局部丢弃；空结果归一为 `nil`，不触发后续工具链路异常循环。

4. Given `function.arguments` 是 JSON 字符串
   When 解码 `ChatResponseBody`
   Then `argumentsRaw` 保留原值；若可解析为对象则填充 `arguments`。

5. Given `function.arguments` 是 JSON 对象
   When 解码 `ChatResponseBody`
   Then `arguments` 填充对象字典；`argumentsRaw` 生成 canonical JSON（compact + sortedKeys）。

6. Given `function.arguments` 是数组/布尔/数字等非对象 JSON
   When 解码 `ChatResponseBody`
   Then 保留 `argumentsRaw`（canonical JSON），`arguments` 为空，整包不失败。

7. Given 解码失败（例如核心字段缺失或不可恢复结构错误）
   When `OpenAIClient` 抛错
   Then 错误信息包含 `codingPath`、`model/url` 和截断响应片段，便于定位。

## 验收标准

- 新增兼容测试覆盖上述场景并通过。
- 历史标准 OpenAI 样例 decode 行为不回归。
- 现有调用方 API 无改动，`SKILanguageModelSession` 工具调用链路可继续使用 `argumentsRaw`。
