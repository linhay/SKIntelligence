# Skills Index

本页提供项目技能入口。`docs-dev` 可以引用 `skills`，但 `skills` 不反向引用 `docs-dev`。

## skintelligence

- 位置：`skills/skintelligence`
- 定位：SKIntelligence 全库方法型开发技能（ACP/CLI/回归/联调/测试门禁）。
- 主文件：`skills/skintelligence/SKILL.md`
- 快速命令：
  - `skills/skintelligence/scripts/check_skill_boundary.sh`
  - `skills/skintelligence/scripts/run_acp_regression.sh`
  - `skills/skintelligence/scripts/run_library_smoke.sh`
  - `skills/skintelligence/scripts/run_targeted_tests.sh ACPProtocolConformanceTests`
  - `skills/skintelligence/scripts/run_codex_connect_smoke.sh`

## 使用约束

1. 只允许 `docs-dev/* -> skills/*` 单向引用。
2. 技能内方法必须自包含，不依赖 `docs-dev` 路径跳转。
3. 项目需求、架构与治理文档继续以 `docs-dev` 为主。
