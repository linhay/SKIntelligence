# CLI TUI Spec

## 背景

`ski` 需要提供默认可交互聊天入口，并复用 ACP 链路连接后端（`ski acp serve`、`codex-acp` 或其他 ACP 兼容服务）。

## 目标

1. `ski`（无子命令）直接进入聊天页。
2. `ski tui` 作为显式等价入口保留。
3. 默认 profile 为空，不自动连接。
4. 聊天页输入 `/` 自动弹选择器，完成连接/会话/UI 操作。
5. 使用全屏 + 差量重绘 + 流式更新，降低闪烁并保持响应。

## 非目标

1. 不做鼠标交互。
2. 不做多会话 Tab。
3. 不做 Markdown 富渲染。
4. 不提供 `Ctrl+O` 连接 Overlay 入口。

## BDD 验收场景

### 场景 1：根命令默认聊天
- Given 用户在交互终端执行 `ski`
- When 命令启动
- Then 进入 TUI 聊天页
- And 状态为 `Disconnected`

### 场景 2：根命令非 TTY 保护
- Given 用户在非交互环境执行 `ski`
- When 命令启动
- Then 退出码为 `2`
- And stderr 包含 `ski defaults to chat mode and requires an interactive TTY`

### 场景 3：显式 TUI 帮助
- Given 用户执行 `ski tui --help`
- When 命令返回
- Then 退出码为 `0`
- And 帮助包含 `Interactive terminal UI`、`--transport`、`--cmd`

### 场景 4：参数边界校验
- Given 用户执行 `ski tui --transport stdio --endpoint ws://...`
- When 命令校验参数
- Then 退出码为 `2`
- And stderr 包含 `--endpoint is only valid for ws transport`

### 场景 5：Slash 选择器连接
- Given 用户在聊天页输入 `/`
- When Slash 菜单弹出并选择 `Connect`
- Then 使用当前连接配置建立 ACP 客户端连接
- And 成功后状态切换为 `Connected`

### 场景 6：流式消息与退出恢复
- Given 用户已连接并发送 prompt
- When agent 持续返回 `session/update` 文本块
- Then TUI 增量追加 assistant 消息
- And 按 `Esc`（无菜单）或 `Ctrl+C` 时退出并恢复终端

## Slash 菜单范围（首版）

1. 连接项：`Connect`、`Reconnect`、`Disconnect`、`Set Transport`、`Set Cmd`、`Set Args`、`Set Endpoint`、`Set Cwd`、`Set Session ID`
2. 会话项：`New Session`、`Load Session`、`Stop Session`
3. UI 项：`Clear Transcript`、`Export Transcript`、`Set Log Level`

## 技术约束

1. 渲染层使用 ANSI Alternate Screen（`?1049h` / `?1049l`）与差量刷新。
2. 输入层使用原始模式 + 非阻塞读取，支持字符编辑和方向键。
3. 网络层复用 `ACPClientService` 与 `ACPCLITransportFactory`。
4. 非交互终端不允许进入 TUI。
