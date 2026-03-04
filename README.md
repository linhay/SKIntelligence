# SKIntelligence

SKIntelligence 是一个强大的智能组件库，提供了与大语言模型（LLM）交互的高级功能，包括流式输出、工具调用以及 Model Context Protocol (MCP) 支持。

当前版本发布基线：`2.0.0`

## 文档

详细文档请参考 `docs-dev` 目录：

- [快速上手 (Getting Started)](docs-dev/dev/Getting-Started.md)
  - 从核心类型入口快速跑通：会话、流式、工具、记忆、MCP、CLIP。
- [CI 自动打 Tag + Bark 通知](docs-dev/ops/CI-AutoTag.md)
  - Swift CI 通过后自动递增语义化版本最后一位并推送 tag，可选 Bark 通知。
- [Release 2.0.0](docs-dev/ops/Release-2.0.0.md)
  - 大版本发布主文档（范围、迁移、执行清单、回滚）。
- [Release 2.0.0（GitHub Short）](docs-dev/ops/Release-2.0.0-GitHub-Short.md)
  - GitHub Release 精简文案。
- [Release 2.0.0（GitHub Full）](docs-dev/ops/Release-2.0.0-GitHub-Full.md)
  - GitHub Release 完整文案。
- [MLX E2E Runbook](docs-dev/ops/MLX-E2E-Runbook.md)
  - MLX/VLM 环境准备、冒烟和故障排查。

### 核心功能

- [流式输出 (Streaming Output)](docs-dev/dev/Streaming.md)
  - 了解如何使用 `SKIResponseStream` 进行流式响应处理。
- [Model Context Protocol (MCP)](docs-dev/dev/MCP.md)
  - 了解如何连接和管理 MCP 服务器及工具。

### 组件文档

- [SKITextIndex](docs-dev/features/SKITextIndex.md)
  - 专门用于文本块搜索的索引结构，适合 OCR 搜索场景。
  - [性能报告](docs-dev/dev/SKITextIndex-Performance.md)
  - [优化总结](docs-dev/dev/SKITextIndex-Optimization.md)

## 发布与运维

- 发布脚本：`scripts/release_major.sh`
  - 支持 `release` / `rollback`，默认 `DRY_RUN=1` 安全模式。
