# SKIntelligence

SKIntelligence 是一个强大的智能组件库，提供了与大语言模型（LLM）交互的高级功能，包括流式输出、工具调用以及 Model Context Protocol (MCP) 支持。

## 文档

详细文档请参考 `Documentation` 目录：

- [快速上手 (Getting Started)](Documentation/Getting-Started.md)
  - 从核心类型入口快速跑通：会话、流式、工具、记忆、MCP、CLIP。
- [CI 自动打 Tag + Bark 通知](Documentation/CI-AutoTag.md)
  - Swift CI 通过后自动递增语义化版本最后一位并推送 tag，可选 Bark 通知。

### 核心功能

- [流式输出 (Streaming Output)](Documentation/Streaming.md)
  - 了解如何使用 `SKIResponseStream` 进行流式响应处理。
- [Model Context Protocol (MCP)](Documentation/MCP.md)
  - 了解如何连接和管理 MCP 服务器及工具。

### 组件文档

- [SKITextIndex](Documentation/SKITextIndex.md)
  - 专门用于文本块搜索的索引结构，适合 OCR 搜索场景。
  - [性能报告](Documentation/SKITextIndex-Performance.md)
  - [优化总结](Documentation/SKITextIndex-Optimization.md)
