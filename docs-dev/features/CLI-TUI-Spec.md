# CLI TUI Spec（Retired）

## 状态

该规格已于 2026-03-06 退役，不再作为当前产品目标。

## 退役原因

1. 产品方向收敛为 ACP 后端服务。
2. `ski` 根命令不再进入聊天页，而是显示 help。
3. `ski tui` 子命令与相关实现、测试已移除。

## 当前替代行为

1. 服务端入口：`ski acp serve`
2. 客户端入口：`ski acp client ...`
3. 版本查询：`ski --version` / `ski version`

## 迁移说明

1. 需要查看命令入口时，执行 `ski --help`
2. 需要启动 ACP 服务时，执行 `ski acp serve --help`
3. 需要联调客户端时，执行 `ski acp client --help`
