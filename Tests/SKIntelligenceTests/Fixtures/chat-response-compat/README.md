# chat-response-compat fixtures

来源均为官方文档示例（抓取日期：2026-02-28）：

- OpenAI Cookbook:
  - https://cookbook.openai.com/examples/how_to_call_functions_with_chat_models
  - 文件：`openai_cookbook_tool_call_response.json`
- 阿里云 DashScope OpenAI 兼容文档：
  - https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope
  - 文件：`dashscope_http_chat_response.json`
- DeepSeek API Reference:
  - https://api-docs.deepseek.com/api/create-chat-completion
  - 文件：`deepseek_api_schema_tool_call_response.json`

说明：

- 为保证 `ChatResponseBody` 解码回归稳定，fixture 保留官方示例中的关键字段并去除与本库无关字段。
- 每个 JSON 含 `_source` 与 `_note` 字段用于追溯，解析时会被 `Decodable` 忽略。
