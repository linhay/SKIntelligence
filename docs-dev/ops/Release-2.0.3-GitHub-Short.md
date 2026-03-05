# SKIntelligence 2.0.3

发布日期：2026-03-05

## TL;DR

`2.0.3` 是 `2.0.2` 的 TUI 修复补丁版本，修复中文等 UTF-8 输入被吞、宽字符渲染错位等问题。

## 主要变化

- 修复 TUI 输入解析：
  - `TUIByteParser` 新增 UTF-8 多字节序列解析；
  - 处理分片输入，避免中文输入中途丢字。
- 修复 TUI 终端渲染：
  - 输入框、换行、补齐、裁剪改为按终端列宽计算；
  - 初始化 `LC_CTYPE` 并使用 `wcwidth`，改善中日韩宽字符光标/对齐。
- 新增回归测试：
  - `TUIByteParserTests` 覆盖 ASCII、完整 UTF-8、分片 UTF-8 场景。

## 验证

- 测试：`swift test --filter TUIByteParserTests --filter SKICLIProcessTests`（108/108 PASS）
- 冒烟：
  - `acp serve(ws) + tui` 自动交互下，`你好，回复OK` 输入与 `[echo]` 回包均可见；
  - 对比 `brew` 已安装 `2.0.2` 可稳定复现“中文不显示”，确认本次修复有效。
