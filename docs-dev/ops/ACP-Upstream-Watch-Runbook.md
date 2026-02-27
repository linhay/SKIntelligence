# ACP Upstream Watch Runbook

## 目标
- 持续跟踪 ACP 官方仓库与官网文档变化。
- 将上游变化分级为 `P0/P1/P2`，驱动本仓库对齐优先级。

## 数据源
- GitHub 组织：`agentclientprotocol`
- 核心仓库（固定）：`spec`、各语言 SDK
- 扩展仓库（自动）：组织内全部仓库

## 执行命令
```bash
./scripts/acp_upstream_watch.sh
```

可选参数：
```bash
ACP_UPSTREAM_SINCE_DAYS=1 \
ACP_UPSTREAM_ORG=agentclientprotocol \
ACP_UPSTREAM_DAILY_FILE=docs-dev/ops/acp-upstream-daily.md \
ACP_UPSTREAM_REPOS=agentclientprotocol/agent-client-protocol \
ACP_UPSTREAM_SKIP_ORG_SCAN=1 \
./scripts/acp_upstream_watch.sh
```

## 输出文件
- 默认输出：`docs-dev/ops/acp-upstream-daily.md`
- 内容：
  - 每日汇总（仓库数量、P0/P1/P2 聚合）
  - schema 漂移摘要（stable/unstable missingLocal/extraLocal）
  - compatibility 扩展与上游重叠检查（用于提示迁移到 official baseline）
  - Priority Items（P0/P1 明细：repo/title/url/updatedAt）
  - 每仓库快照（默认分支、HEAD、最新 Release、风险信号）

环境变量补充：
- `ACP_UPSTREAM_REPOS`：逗号或空格分隔的仓库列表；设置后仅扫描指定仓库。
- `ACP_UPSTREAM_SKIP_ORG_SCAN=1`：关闭组织仓库自动扩展（用于本地快速验证/CI 控制范围）。

## 分级规则
- `P0`: `breaking/deprecate/protocol/schema/json-rpc/transport`
- `P1`: `sdk/client/server/example/tool/session/permission`
- `P2`: `doc/readme/typo/format/chore`

## 联动动作
- 命中 `P0`：当天建对齐任务，补回归场景。
- 命中 `P1`：周内排期，纳入周报。
- 命中 `P2`：仅记录，不触发紧急开发。
- 命中 `P0/P1`：优先从报告 `Priority Items` 章节拉取明细并分配 owner。

## 建议节奏
- 每日两次：10:00 / 16:00（本地时区）
- 每周一次复盘：汇总本周 P0/P1 项并确认对齐状态
