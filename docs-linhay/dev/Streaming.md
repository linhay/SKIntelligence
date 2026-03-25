# SKIntelligence 流式输出 (Streaming Output)

SKIntelligence 提供了现代化的 Swift 异步流（AsyncSequence）接口，用于处理流式响应。这使得处理实时生成的文本、推理内容和工具调用变得非常简单。

## 基础用法

使用 `OpenAIClient` 的 `streamingRespond` 方法获取 `SKIResponseStream`，然后通过 `for-await-in` 循环处理数据块。

```swift
import SKIntelligence
import SKIClients

let client = OpenAIClient().profiles([
    .init(
        url: URL(string: OpenAIClient.EmbeddedURL.openai.rawValue)!,
        token: "your-api-key",
        model: "gpt-4"
    )
])

// 构建请求主体
let body = ChatRequestBody(messages: [
    .init(role: .user, content: "给我讲一个关于编程的笑话")
])

// 1. 获取流
let stream = try await client.streamingRespond(body)

// 2. 迭代处理数据块
for try await chunk in stream {
    // 处理文本内容
    if let text = chunk.text {
        print(text, terminator: "")
    }
    
    // 处理推理内容 (对于支持 Chain of Thought 的模型)
    if let reasoning = chunk.reasoning {
        print("[Thinking: \(reasoning)]")
    }
}
```

## 便捷方法

如果你只需要最终的完整文本或推理内容，可以使用便捷方法：

```swift
let stream = try await client.streamingRespond(body)

// 聚合所有文本块
let fullText = try await stream.text()
print("完整回复: \(fullText)")

// 或者聚合所有推理内容
// let fullReasoning = try await stream.reasoning()
```

## 处理工具调用

流式响应也支持工具调用。`SKILanguageModelSession` 会自动处理工具调用的累积和执行。

```swift
let session = SKILanguageModelSession(client: client, tools: [MyTool()])

let stream = try await session.streamResponse(to: "查询北京的天气")

for try await chunk in stream {
    // 实时显示的文本响应
    if let text = chunk.text {
        print(text, terminator: "")
    }
    
    // session 会自动处理 chunk.toolRequests 并执行工具
    // 如果你需要监听工具调用的产生，可以检查 chunk.toolRequests
}
```

## Token Usage 追踪（会话聚合）

从 2026-03-01 起，`SKILanguageModelSession` 会在会话内累计 token 统计（仅 token，不含金额）：

- `promptTokens`
- `completionTokens`
- `totalTokens`
- `reasoningTokens`
- `requestsCount`

流式路径会自动开启 `stream_options.include_usage = true`，并在收到 usage chunk 后计入会话累计。

```swift
let session = SKILanguageModelSession(client: client)

_ = try await session.respond(to: "hello")
let stats1 = await session.tokenUsageSnapshot()

let stream = try await session.streamResponse(to: "继续")
for try await _ in stream {}
let stats2 = await session.tokenUsageSnapshot()

await session.resetTokenUsage()
let stats3 = await session.tokenUsageSnapshot() // 全部归零
```

## 多 Profile 顺序回退

`OpenAIClient` 支持用 `profiles` 配置多个推理端点（每个 profile 含 `url/token/model/headerFields`），并按数组顺序回退。

```swift
import SKIClients
import HTTPTypes

let primary = OpenAIClient.EndpointProfile(
    url: URL(string: "https://primary.example.com/v1/chat/completions")!,
    token: "primary-token",
    model: "gpt-4o-mini"
)

var fallbackHeaders = HTTPFields()
fallbackHeaders[.authorization] = "Bearer fallback-token"
let fallback = OpenAIClient.EndpointProfile(
    url: URL(string: "https://fallback.example.com/v1/chat/completions")!,
    token: "ignored-when-authorization-present",
    model: "gpt-4o-mini",
    headerFields: fallbackHeaders
)

let client = OpenAIClient()
    .profiles([primary, fallback])

// streaming 在连接失败且尚未收到 chunk 时会自动尝试下一个 profile
let stream = try await client.streamingRespond(ChatRequestBody(messages: [
    .user(content: .text("hello"))
]))
```

注意：当 `profiles` 为空时，`respond/streamingRespond` 会立即返回配置错误。
