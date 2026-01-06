# SKIntelligence 流式输出 (Streaming Output)

SKIntelligence 提供了现代化的 Swift 异步流（AsyncSequence）接口，用于处理流式响应。这使得处理实时生成的文本、推理内容和工具调用变得非常简单。

## 基础用法

使用 `OpenAIClient` 的 `streamingRespond` 方法获取 `SKIResponseStream`，然后通过 `for-await-in` 循环处理数据块。

```swift
import SKIntelligence

let client = OpenAIClient()
client.token = "your-api-key"
client.model = "gpt-4"

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
