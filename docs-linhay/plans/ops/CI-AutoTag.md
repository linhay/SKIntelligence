# CI: Auto Tag (SemVer Patch +1) & Bark Notification

本页说明本仓库的 GitHub Actions 工作流：

- 当 Swift CI 通过后，自动为本次提交创建一个语义化版本 tag
- 版本策略：只自动递增 `PATCH`（最后一位）
- 完成后向 Bark 发送通知（可选）

对应 workflow 文件：

- `.github/workflows/auto-tag.yml`

## 触发条件

该 workflow 通过 `workflow_run` 触发，而不是直接 `push`：

- 监听 workflows: `Swift`
- 类型：`completed`
- 分支：`main` / `master`
- 仅当满足以下条件才运行 job：
  - `conclusion == success`
  - `event == push`

这样做的好处：

- 只有测试/构建通过才打 tag（避免失败构建也产生版本）

## Tag 规则（SemVer）

### 支持的 tag 格式

只识别严格语义化版本三段式：

- `1.2.3`
- `v1.2.3`

其他格式（例如 `1.2`、`1.2.3-beta1`、`release-1.2.3`）不会参与自动版本计算。

### 计算方式

- 找到仓库中“最新”的 semver tag（按版本号排序）
- 读取 `MAJOR.MINOR.PATCH`
- 生成下一个版本：`PATCH + 1`

举例：

- 最新是 `1.3.2` → 下一个是 `1.3.3`
- 最新是 `v1.3.2` → 下一个是 `v1.3.3`

> 前缀策略：如果最新 tag 带 `v`，下一次也带 `v`；如果不带，则不加。

### 幂等（避免重复打 tag）

如果当前提交（HEAD）已经存在一个 semver tag（例如你手动打过 `1.3.2`），workflow 会：

- 输出 `action=skipped`
- 直接结束，不会重复创建

### 并发保护

在极少数并发情况下（例如多个 workflow 几乎同时尝试创建同一个 `1.3.3`），脚本会：

- 检测 `refs/tags/<next>` 是否已存在
- 若存在则继续 `PATCH+1`，直到找到未被占用的版本

## Bark 通知（可选）

### 为什么必须用 Secret

Bark key 是敏感信息，不应写入仓库文件。

workflow 通过 `secrets.BARK_KEY` 读取 key：

- 未配置 `BARK_KEY`：会打印提示并跳过通知
- 配置了 `BARK_KEY`：会发送通知

### 配置方式

在 GitHub 仓库页面：

- `Settings` → `Secrets and variables` → `Actions`
- `New repository secret`
- Name：`BARK_KEY`
- Value：你的 Bark key（例如 URL 中那段 token）

### 通知内容

- 标题（URL path segment）：`SKIntelligence-<created|skipped>-<tag>`
- body（以多行文本发送）：
  - `repo=<owner/repo>`
  - `sha=<commit sha>`
  - `status=<success|failure|cancelled>`

### 通知失败不影响 CI

Bark 请求使用 `curl ... || true`：

- 即使通知失败，workflow 也不会因此失败

## 权限

workflow 需要推送 tag，因此配置：

- `permissions: contents: write`

并使用内置：

- `secrets.GITHUB_TOKEN`

## 常见问题（FAQ）

### 1) 为什么我的 tag 没变？

可能原因：

- 当前提交已经存在 semver tag（workflow 会 skip）
- 最新 tag 不是 `x.y.z` 或 `vx.y.z`，不会被识别
- 触发的 workflow 不是来自 `push`（例如 `workflow_dispatch`/`pull_request`），job 条件不满足

### 2) 我想自动递增 MINOR 或 MAJOR

当前策略只做 patch +1。

如果你希望：

- 每次合并到 main 自动 `MINOR+1` 并重置 patch
- 或通过 commit message / label 决定 bump 规则

可以再扩展脚本逻辑。

### 3) 我之前把 Bark key 提交进仓库了怎么办？

建议：

- 立刻更换/作废旧 key
- 使用 `BARK_KEY` secret 注入新 key
- 避免在 workflow/文档中再次出现明文 key
