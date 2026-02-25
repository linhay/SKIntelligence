# SKIntelligence CLI 对标规格（v0）

## 1. 背景与目标
SKIntelligence 需要一个可长期演进的 CLI。当前先基于以下参考实现进行对标：
- `openai/codex`
- `google-gemini/gemini-cli`
- `badlogic/pi-mono`

目标：先定义 v0 可交付范围，确保可用、可测、可扩展。

## 2. 用户与核心价值
- 研发用户：在终端发起 AI 编码/问答任务。
- 团队用户：可统一配置 provider、模型、上下文与日志。

核心价值：
- 一条命令启动，低学习成本。
- 清晰的错误与退出码，便于脚本集成。
- 对后续 Agent/Tool 扩展友好。

## 3. 功能范围（v0）
必须包含：
- `chat`：一次性问答（非交互）。
- `run`：执行一个任务并输出结果。
- `config`：查看/设置 provider、model、endpoint、api key 来源。
- `version`：输出版本与构建信息。

暂不包含（v1+）：
- 多会话持久化 UI。
- 浏览器自动化集成。
- 复杂插件生态。

## 4. BDD 验收场景
1. 场景：非交互问答成功
- Given 用户已配置可用 provider 与 model
- When 执行 `ski chat "解释 SKIntelligence 的用途"`
- Then 终端输出文本答案
- And 进程退出码为 `0`

2. 场景：缺失配置时失败
- Given 用户未配置 provider 或 api key
- When 执行 `ski run "summarize README"`
- Then 输出可操作的错误提示（包含如何配置）
- And 进程退出码为非 `0`

3. 场景：脚本集成可预测
- Given 在 CI 或 shell 脚本中调用 CLI
- When 执行 `ski version --json`
- Then 输出稳定 JSON 字段：`name`、`version`、`commit`
- And 进程退出码为 `0`

4. 场景：配置可查询
- Given 用户已设置 provider 与 model
- When 执行 `ski config get`
- Then 输出当前生效配置
- And 不泄露明文敏感信息

5. 场景：ACP client 参数校验（stdio）
- Given 用户执行 `ski acp client connect --transport stdio`
- When 未提供 `--cmd`
- Then CLI 立即返回可读错误 `--cmd is required for stdio transport`
- And 不尝试建立传输连接

6. 场景：ACP client 参数校验（ws）
- Given 用户执行 `ski acp client connect --transport ws`
- When 未提供合法 `--endpoint`
- Then CLI 立即返回可读错误 `--endpoint is required for ws transport`
- And 不尝试建立传输连接

7. 场景：参数错误退出码稳定
- Given CLI 在参数校验阶段失败（如缺失 `--cmd`）
- When 命令结束
- Then 退出码映射为 `2`

8. 场景：ACP JSON 输出结构稳定
- Given 用户执行 `ski acp client connect --json`
- When 收到 `session/update` 通知与最终 prompt 结果
- Then 输出 JSON 字段集合稳定且可解析：
- And `session/update` 包含 `type/sessionId/update/text`
- And 最终结果包含 `sessionId/stopReason`

9. 场景：上游链路失败退出码稳定
- Given 用户执行 `ski acp client connect --transport ws --endpoint ws://127.0.0.1:1`
- When 连接阶段失败
- Then 命令退出码为 `4`
- And stderr 输出上游错误摘要

10. 场景：ACP serve listen 参数校验
- Given 用户执行 `ski acp serve --transport ws --listen invalid`
- When `listen` 不是合法 `host:port`（port 不在 1...65535）
- Then CLI 立即返回参数错误
- And 命令退出码为 `2`

11. 场景：进程级退出码回归自动化
- Given CI 运行 CLI 黑盒测试
- When 执行参数错误与上游连接失败命令
- Then 退出码分别稳定为 `2` 与 `4`
- And stderr 包含对应错误摘要

12. 场景：stdio 子进程命令支持 PATH 解析
- Given 用户执行 `ski acp client connect-stdio`
- And `--cmd` 传入的是 PATH 中可执行命令名（如 `env`、`swift`）
- When CLI 创建 stdio transport
- Then 应自动解析为可执行路径并正常启动子进程
- And 不要求用户必须传绝对路径

13. 场景：help 明确 `--cmd` 的 PATH 语义
- Given 用户执行 `ski acp client connect-stdio --help`
- When 查看 `--cmd` 参数说明
- Then 文案应明确可传“可执行路径或 PATH 中命令名”

14. 场景：help 说明 `--args` 的 option-like 传参规则
- Given 用户执行 `ski acp client connect-stdio --help`
- When 子参数以 `-` 开头（如 `--transport`）
- Then 文案应明确使用 `--args=--flag` 形式，避免被父命令解析

## 5. 非功能要求
- 性能：冷启动命令（`version`）在本地开发机应 < 500ms（目标值）。
- 可观测性：支持 `--verbose` 打印请求链路关键节点。
- 安全：默认不在日志输出完整 token/key。

## 6. DoD（本功能）
- 上述 BDD 场景均有自动化测试。
- 文档与示例命令可直接运行。
- 失败场景具备稳定错误码约定。
