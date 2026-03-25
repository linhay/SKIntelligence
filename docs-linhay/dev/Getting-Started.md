# Getting Started

本页面向第一次使用 SKIntelligence 的使用者，目标是用最少的步骤跑通：

- 创建一次对话请求
- 开启流式输出
- 了解工具调用与记忆（Memory）的大致入口
- 了解 MCP 与 SKIClip 的定位

> 说明：示例以 Swift Package Manager (SPM) 为主。具体 API 以源码为准，文档会优先给出“从哪几个类型入手”。

## 安装

在你的项目 `Package.swift` 中添加依赖（示意）：

- 依赖：本仓库（或你内部的 Git 地址）
- target dependencies：`SKIntelligence`

如果你在本仓库内开发：

- 运行测试：`swift test`

## 模块结构（你应该从哪里看起）

技能入口：

- [Skills-Index.md](Skills-Index.md)

核心 LLM 能力在 `Sources/SKIntelligence/`：

- `SKILanguageModelClient`：抽象的模型客户端（不同供应商可各自实现）
- `SKILanguageModelSession`：一次“会话/对话”的编排入口（通常从这里开始用）
- `SKIPrompt` / `SKIModelSection`：构造提示词与上下文
- `SKIResponse`：一次响应（非流式）
- `Stream/SKIResponseStream`：流式响应
- `SKITool` / `SKIToolError`：工具调用

额外能力：

- `Sources/SKIntelligence/Memory/`：对话记忆（Conversation / Summary 等）
- `Sources/SKIntelligence/MCP/`：Model Context Protocol 客户端与工具管理
- `Sources/SKIClip/`：CLIP 向量化与相似度/索引（偏多模态/向量检索）

## 最小使用路径（建议按这个顺序）

1. 先决定你要用哪个模型供应商
2. 通过 `SKILanguageModelClient`（或其具体实现）创建会话 `SKILanguageModelSession`
3. 用 `SKIPrompt` 组织输入
4. 根据需要选择：
   - 非流式：得到一个 `SKIResponse`
   - 流式：使用 `SKIResponseStream` 逐步消费增量

## 可运行的最小示例（本仓库内）

本仓库内置了一个 SwiftPM 可执行示例 target：`SKIntelligenceExample`。

入口代码：

- `Sources/SKIntelligenceExample/main.swift`

### 运行（需要 API Key）

在仓库根目录执行：

- `OPENAI_API_KEY=你的key swift run SKIntelligenceExample`

可选环境变量：

- `OPENAI_MODEL`：默认 `gpt-4`
- `OPENAI_BASE_URL`：自定义 OpenAI Compatible 网关地址（例如 OpenRouter / DeepSeek / 内部网关）

示例会跑两段：

- 非流式：`session.respond(to:)`
- 流式：`session.streamResponse(to:)`

如果你没有配置 `OPENAI_API_KEY`，示例会直接退出并打印提示（用于保证“可运行但不强依赖外部服务”）。

## 流式输出（Streaming）

流式相关细节见：

- [Streaming.md](Streaming.md)

你通常会在流式响应中做两件事：

- 增量渲染/拼接内容（例如 UI 中逐字输出）
- 监听工具调用（如果模型触发 tool call）并执行工具

相关类型（源码入口）：

- `ChatStreamDelta`
- `SKIResponseStream`
- `ToolCallCollector`

## 工具调用（Tools）

工具调用的核心抽象在：

- `SKITool`

你可以将工具理解为：模型可以请求你执行一些“可调用函数”，例如查询日历、地理位置、搜索等。

本仓库提供了一些工具实现（见 `Sources/SKITools/`）：

- `SKIToolLocalDate`
- `SKIToolLocalLocation`
- `SKIToolQueryCalendar`
- `SKIToolReverseGeocode`
- `SKIToolTavilySearch`
- `BaiduAPIs/*`（翻译等）

## 记忆（Memory）

记忆相关类型在 `Sources/SKIntelligence/Memory/`。

你可以把它理解为：

- `SKIConversationMemory`：保存对话轮次
- `SKISummaryMemory`：在对话很长时做摘要压缩
- `SKIMemoryStore` / `SKIInMemoryStore`：存储层抽象/默认实现

当你需要“长对话且成本可控”的体验时，建议看：

- `SKISummarizer`

## MCP（Model Context Protocol）

MCP 能让你把外部工具/服务以统一方式接入，让模型“像调用工具一样”访问外部能力。

入口文档：

- [MCP.md](MCP.md)

源码入口（`Sources/SKIntelligence/MCP/`）：

- `SKIMCPClient`
- `SKIMCPManager`
- `SKIMCPTool`

## SKIClip（CLIP / 向量化与检索）

如果你要做：

- 图像/文本向量化
- 相似度计算
- 向量索引（例如 OCR 搜索、相似内容召回）

可以从 `Sources/SKIClip/` 入手：

- `CLIPEncoder`
- `SKISimilarity` / `SKISimilarityIndex`
- `SKITextIndex`（另外有专门文档）

相关文档：

- [SKITextIndex.md](../features/SKITextIndex.md)

## 常见问题（FAQ）

### 我应该从哪个测试用例看起？

可以从 `Tests/SKIntelligenceTests/` 里挑与你关注能力相关的：

- `SKIStreamingTests.swift`（流式）
- `SKIMCPIntegrationTests.swift`（MCP）
- `SKIMemoryTests.swift`（记忆）
- `SKITextIndexTests.swift`（索引）

### Tag/发布版本怎么走？

见 [CI-AutoTag.md](../ops/CI-AutoTag.md)。
