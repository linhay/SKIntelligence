# Release 1.3.17

发布日期：2026-02-28

## 变更摘要

- 修复 `ChatResponseBody` 在 OpenAI-compatible `tool_calls` 响应上的解码兼容问题。
- 保持对外单模型输出（`ChatResponseBody`），兼容逻辑收敛在解码层（内部 Raw + normalize）。
- 增强 `OpenAIClient` 解码失败诊断：包含 `codingPath`、`model`、`url`、`responseSnippet`，并对敏感字段脱敏。

## 行为改进

1. `message.content` 兼容：
- `string`
- `null`
- `[]`
- `[{type,text}]`

2. `message.tool_calls` 兼容：
- `missing`
- `null`
- `[]`
- 部分坏项（坏项局部丢弃，保留可解析项）

3. `function.arguments` 兼容：
- 字符串 JSON：保留 `argumentsRaw`，可解析对象时填充 `arguments`
- 对象 JSON：填充 `arguments`，并生成 canonical `argumentsRaw`（compact + sortedKeys）
- 非对象 JSON：保留 canonical `argumentsRaw`，`arguments` 置空

## 回归测试

- `ChatResponseBodyCompatibilityTests`
- `OpenAIClientDecodingDiagnosticsTests`
- 官方文档 fixture：
  - OpenAI Cookbook
  - DashScope OpenAI 兼容文档
  - DeepSeek API 文档

## 使用示例

```swift
import SKIClients
import SKIntelligence

let client = OpenAIClient()
    .token(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "")
    .model("gpt-4o-mini")

let response = try await client.respond(
    ChatRequestBody(
        messages: [.user("What's the weather in Hangzhou?")],
        tools: [
            .function(
                .init(
                    name: "get_weather",
                    description: "Get weather",
                    parameters: .object(
                        properties: [
                            "location": .string()
                        ],
                        required: ["location"]
                    )
                )
            )
        ]
    )
)

if let call = response.content.choices.first?.message.toolCalls?.first {
    print(call.function.name)
    print(call.function.argumentsRaw ?? "")
}
```
