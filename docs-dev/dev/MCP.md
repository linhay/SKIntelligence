# SKIntelligence Model Context Protocol (MCP)

[Model Context Protocol (MCP)](https://github.com/modelcontextprotocol) 是一个开放标准，允许 AI 模型安全地访问本地或是远程的数据和工具。SKIntelligence 内置了 `SKIMCPManager` 来管理 MCP 服务器连接。

## 核心功能

- **多服务器管理**: 同时连接多个 MCP 服务器。
- **自动连接**: 注册即自动建立 SSE 连接。
- **工具聚合**: 获取所有已连接服务器提供的工具。

## 使用指南

### 1. 注册 MCP 服务器

使用 `SKIMCPManager.shared` 注册 MCP 服务器。你需要提供唯一的 ID 和 SSE 端点 URL。

```swift
import SKIntelligence

// 获取单例
let manager = SKIMCPManager.shared

// 注册本地或远程 MCP 服务器
// 例如，一个本地运行的 filesystem server
let endpoint = URL(string: "http://localhost:3000/sse")!

try await manager.register(
    id: "filesystem-server",
    endpoint: endpoint,
    headers: ["Authorization": "Bearer token"] // 可选
)
```

### 2. 获取和使用工具

注册后，你可以获取所有服务器提供的工具，并将它们提供给 `SKILanguageModelSession`。

```swift
// 获取所有已注册服务器的工具
let tools = try await manager.getAllTools()

// 创建 Session 并注入 MCP 工具
let session = SKILanguageModelSession(
    client: client,
    tools: tools // 直接使用 [SKIMCPTool]
)

// 现在模型可以调用 MCP 服务器提供的工具了
let response = try await session.chat(with: "列出当前目录下的所有文件")
```

### 3. 管理连接

```swift
// 断开并移除特定服务器
await manager.unregister(id: "filesystem-server")

// 断开所有连接
await manager.disconnectAll()
```

## 架构说明

`SKIMCPClient` 负责单个 MCP 连接的底层通信（基于 SSE 和 JSON-RPC），而 `SKIMCPManager` 在此之上提供了统一的管理层。在构建 AI 助手时，通常只需要与 `SKIMCPManager` 交互。
