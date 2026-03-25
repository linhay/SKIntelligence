# CLI 分发安装实现说明

关联需求：`docs-linhay/features/CLI-Distribution-Install-Spec.md`

## 实现范围

1. `scripts/package_cli.sh`
   - 负责构建并打包 `ski` 二进制。
   - 输出：
     - `dist/cli/ski-macos-arm64.tar.gz`
     - `dist/cli/ski-macos-arm64.sha256`
     - `dist/cli/ski-macos-x86_64.tar.gz`
     - `dist/cli/ski-macos-x86_64.sha256`
2. `scripts/install_ski.sh`
   - 默认通过 GitHub `releases/latest` 解析版本。
   - 根据本机架构下载 `ski-macos-<arch>.tar.gz` 并安装到 `<prefix>/bin/ski`。
3. `scripts/release_major.sh`
   - 新增 `RUN_PACKAGE_CLI`（默认 `1`）。
   - release 流程中调用 `scripts/package_cli.sh` 并附加 `dist/cli` 资产到 GitHub Release。
4. `scripts/generate_homebrew_formula.sh`
   - 从 `dist/cli/*.sha256` 读取校验值并生成 `dist/homebrew/ski.rb`。
   - `release_major.sh` 在 `RUN_HOMEBREW_FORMULA=1` 时自动调用并上传 `ski.rb`。
5. `scripts/sync_homebrew_tap.sh`
   - 把 formula 同步到独立 tap 仓库（默认 `linhay/homebrew-tap`）的 `Formula/ski.rb`。
   - `release_major.sh` 在 `EXPORT_FORMULA_TO_REPO=1` 时自动调用。

## 测试策略

新增 `Tests/SKIntelligenceTests/CLIDistributionScriptsTests.swift`：

1. 安装脚本存在性与 latest API 语义检查。
2. 打包脚本存在性与资产命名检查。
3. 发布脚本包含 CLI 打包与上传逻辑检查。
4. 多个脚本（含 tap 同步脚本）的 `bash -n` 语法检查。
5. Homebrew 生成脚本存在性与 release 集成检查。
