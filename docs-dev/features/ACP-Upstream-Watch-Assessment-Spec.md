# ACP Upstream Watch Assessment Spec

日期：2026-02-27
范围：`scripts/acp_upstream_watch.sh` 生成的每日对齐报告

## 背景
- 现有日报提供 `P0/P1/P2` 聚合计数，但缺少可执行的明细条目。
- 当 `P0 > 0` 时，维护者仍需手工翻查 PR/Issue，处置路径不够短。

## 目标
- 在日报中输出最近窗口内的 `P0/P1` 明细条目（标题、链接、更新时间、仓库）。
- 输出可直接执行的“同日处置动作”提示，降低人工二次整理成本。
- 允许在本地/CI 以最小仓库子集运行 watch（便于测试与排障）。

## 验收场景（BDD）
1. Given 某仓库在窗口内存在命中 `P0` 关键词的 PR
2. When 运行 `./scripts/acp_upstream_watch.sh`
3. Then 报告包含 `## Priority Items` 章节
4. And 章节内包含 `P0` 条目（repo、title、url、updatedAt）
5. And Summary 的 Action 指向“same-day P0 assessment”

6. Given 窗口内没有 `P0/P1` 命中条目
7. When 运行脚本
8. Then `## Priority Items` 中明确输出 `none`

9. Given 维护者只想跟踪一个仓库做本地验证
10. When 设置 `ACP_UPSTREAM_REPOS` 并设置 `ACP_UPSTREAM_SKIP_ORG_SCAN=1`
11. Then 脚本仅扫描指定仓库并成功生成报告
