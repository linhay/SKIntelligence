# SKIntelligence

SKIntelligence 是一个面向 Swift 的 LLM 能力库，提供会话编排、流式输出、工具调用、MCP 接入、记忆与检索能力。

## 安装（Swift Package Manager）

```swift
dependencies: [
    .package(url: "https://github.com/linhay/SKIntelligence.git", from: "2.0.0")
]
```

在 target 中按需添加：

```swift
.target(
    name: "YourApp",
    dependencies: [
        "SKIntelligence",
        "SKIClients",
        "SKITools"
    ]
)
```

## 快速开始

### 1) 初始化客户端

```swift
import SKIntelligence
import SKIClients

let client = OpenAIClient().profiles([
    .init(
        url: URL(string: "https://api.openai.com/v1/chat/completions")!,
        token: "<OPENAI_API_KEY>",
        model: "gpt-4o-mini"
    )
])
```

### 2) 非流式调用

```swift
let session = SKILanguageModelSession(client: client)
let text = try await session.respond(to: "用一句话介绍 SKIntelligence")
print(text)
```

### 3) 流式调用

```swift
let stream = try await session.streamResponse(to: "分三点说明如何接入 MCP")
for try await chunk in stream {
    if let text = chunk.text {
        print(text, terminator: "")
    }
}
```

## 代码示例

### 1) 最小可运行示例（SPM + 一次问答）

`Package.swift`

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SKIDemo",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/linhay/SKIntelligence.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "SKIDemo",
            dependencies: ["SKIntelligence", "SKIClients"]
        )
    ]
)
```

`Sources/SKIDemo/main.swift`

```swift
import Foundation
import SKIntelligence
import SKIClients

@main
struct SKIDemoApp {
    static func main() async throws {
        let client = OpenAIClient().profiles([
            .init(
                url: URL(string: "https://api.openai.com/v1/chat/completions")!,
                token: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "",
                model: "gpt-4o-mini"
            )
        ])

        let session = SKILanguageModelSession(client: client)
        let text = try await session.respond(to: "用一句话介绍 SKIntelligence")
        print(text)
    }
}
```

运行：

```bash
OPENAI_API_KEY=<your_key> swift run
```

## 你可以用它做什么

- 流式输出与增量渲染  
  - 文档：`docs-dev/dev/Streaming.md`
- 工具调用（Tool Calling）  
  - 文档：`docs-dev/dev/Getting-Started.md`
- MCP 工具接入  
  - 文档：`docs-dev/dev/MCP.md`
- 会话记忆（Memory）  
  - 文档：`docs-dev/dev/Getting-Started.md`
- 文本检索/索引（SKITextIndex）  
  - 文档：`docs-dev/features/SKITextIndex.md`

## 进一步阅读

- [快速上手](docs-dev/dev/Getting-Started.md)
- [流式输出](docs-dev/dev/Streaming.md)
- [MCP](docs-dev/dev/MCP.md)
- [SKITextIndex](docs-dev/features/SKITextIndex.md)

## Tools

- 可以在 `SKILanguageModelSession` 中注册工具，让模型按需触发函数调用。
- 内置工具实现位于：`Sources/SKITools/`
- 入口文档：`docs-dev/dev/Getting-Started.md`

```swift
import SKIntelligence
import SKIClients
import SKITools

let client = OpenAIClient().profiles([
    .init(
        url: URL(string: "https://api.openai.com/v1/chat/completions")!,
        token: "<OPENAI_API_KEY>",
        model: "gpt-4o-mini"
    )
])

let session = SKILanguageModelSession(
    client: client,
    tools: [
        SKIToolLocalDate(),
        SKIToolLocalLocation()
    ]
)

let text = try await session.respond(to: "现在几点？并告诉我你所在位置")
print(text)
```

### Tool 回调流式示例

```swift
let stream = try await session.streamResponse(to: "先告诉我现在时间，再告诉我城市")
for try await chunk in stream {
    if let text = chunk.text {
        print(text, terminator: "")
    }
}
```

### 自定义 Tool 定义示例

```swift
import Foundation
import JSONSchemaBuilder
import SKIntelligence

struct WeatherTool: SKITool {
    @Schemable
    struct Arguments {
        @SchemaOptions(.description("城市名，例如 Beijing"))
        let city: String
    }

    @Schemable
    struct ToolOutput: Codable {
        @SchemaOptions(.description("天气描述"))
        let summary: String
        @SchemaOptions(.description("温度（摄氏度）"))
        let temperatureC: Int
    }

    let name = "get_weather"
    let description = "根据城市查询当前天气"

    func displayName(for arguments: Arguments) async -> String {
        "查询天气 [\(arguments.city)]"
    }

    func call(_ arguments: Arguments) async throws -> ToolOutput {
        // 这里替换为你的真实天气 API 逻辑
        .init(summary: "sunny", temperatureC: 26)
    }
}
```

注册并使用：

```swift
let session = SKILanguageModelSession(
    client: client,
    tools: [WeatherTool()]
)

let text = try await session.respond(to: "帮我查一下北京天气")
print(text)
```

## MCP

- 支持接入 MCP Server 并把外部能力暴露为模型可调用工具。
- 文档入口：
  - [MCP 使用说明](docs-dev/dev/MCP.md)
  - [快速上手](docs-dev/dev/Getting-Started.md)

```swift
import SKIntelligence
import SKIClients

let client = OpenAIClient().profiles([
    .init(
        url: URL(string: "https://api.openai.com/v1/chat/completions")!,
        token: "<OPENAI_API_KEY>",
        model: "gpt-4o-mini"
    )
])

let manager = SKIMCPManager.shared
try await manager.register(
    id: "filesystem-server",
    endpoint: URL(string: "http://localhost:3000/sse")!
)

let mcpTools = try await manager.getAllTools()
let session = SKILanguageModelSession(client: client)
await session.register(mcpTools: mcpTools)

let text = try await session.respond(to: "列出当前目录文件")
print(text)
```

### MCP 多轮示例（先注册后复用）

```swift
let session = SKILanguageModelSession(client: client)
await session.register(mcpTools: try await SKIMCPManager.shared.getAllTools())

_ = try await session.respond(to: "先查看目录")
let followup = try await session.respond(to: "再读取 README.md 前 20 行")
print(followup)
```

## ACP

- 提供 ACP Agent/Client/Transport 与 `ski acp` CLI 工作流。
- 常用命令：

```bash
# 启动 ACP 服务端（stdio）
swift run ski acp serve --transport stdio

# 以客户端连接并发起一次 prompt（stdio）
swift run ski acp client connect --transport stdio --cmd ski --args=acp --args=serve --args=--transport --args=stdio --prompt "hello"

# 启动 ACP 服务端（ws）
swift run ski acp serve --transport ws --listen 127.0.0.1:8900

# 以客户端连接并发起一次 prompt（ws）
swift run ski acp client connect --transport ws --endpoint ws://127.0.0.1:8900 --prompt "hello"
```

### ACP 命令链示例（本地联调）

```bash
# 终端 A：启动服务
swift run ski acp serve --transport stdio

# 终端 B：连接并发起请求
swift run ski acp client connect \
  --transport stdio \
  --cmd ski \
  --args=acp --args=serve --args=--transport --args=stdio \
  --prompt "请列出可用工具并执行一个示例"
```

- 文档入口：
  - [ACP 规格覆盖矩阵](docs-dev/dev/ACP-Spec-Coverage-Matrix.md)
  - [ACP WebSocket Serve Spec](docs-dev/features/ACP-WebSocket-Serve-Spec.md)
  - [Codex ACP Runbook](docs-dev/dev/Codex-ACP-Runbook.md)

## Agents Skills 包

本仓库提供可直接给智能体（agents）使用的 skills 包：

- 技能源码目录：`skills/skintelligence/`
- 分发包：`skills/dist/skintelligence.skill`
- 入口文件：`skills/skintelligence/SKILL.md`
- Release 下载页：`https://github.com/linhay/SKIntelligence/releases`
- 2.0.0 直链（发布后可用）：
  - `https://github.com/linhay/SKIntelligence/releases/download/2.0.0/skintelligence.skill`

适用于支持技能包/`SKILL.md` 机制的 agent 运行环境。  
可将 `skintelligence.skill` 导入你的 agent 平台，获得面向本仓库的测试、回归、发布编排等标准化工作流。

## 维护者入口（发布/运维）

- [Release 2.0.0](docs-dev/ops/Release-2.0.0.md)
- [Release 2.0.0 GitHub Short](docs-dev/ops/Release-2.0.0-GitHub-Short.md)
- [Release 2.0.0 GitHub Full](docs-dev/ops/Release-2.0.0-GitHub-Full.md)
- 发布脚本：`scripts/release_major.sh`
