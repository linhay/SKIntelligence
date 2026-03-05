# CLI 分发与安装 Spec

## 背景

当前 `ski` CLI 主要通过源码方式使用（`swift run ski ...`），终端用户缺少稳定安装路径。  
本规格定义发布资产与安装脚本的最小可用能力。

## 目标

1. 发布流程可产出并上传 `ski` CLI 二进制资产。
2. 用户可通过安装脚本在 macOS 上安装 `ski`。
3. README 提供终端用户安装与升级入口。
4. 发布流程可生成 Homebrew Formula 文件。
5. 支持独立 Homebrew tap 仓库同步。

## 验收场景（BDD）

### 场景 1：发布流程包含 CLI 资产

- Given 维护者执行 `scripts/release_major.sh release <version> ...`
- When 发布流程完成
- Then GitHub Release 除 `skintelligence.skill` 外，还应包含：
  - `ski-macos-arm64.tar.gz` 与 `ski-macos-arm64.sha256`
  - `ski-macos-x86_64.tar.gz` 与 `ski-macos-x86_64.sha256`

### 场景 2：安装脚本支持 latest 安装

- Given 用户位于 macOS 环境
- When 执行 `scripts/install_ski.sh` 且未传 `--version`
- Then 脚本应通过 GitHub Releases latest API 解析最新版本
- And 下载对应架构的 `ski-macos-<arch>.tar.gz`
- And 将 `ski` 安装到 `<prefix>/bin/ski`

### 场景 3：安装脚本支持固定版本安装

- Given 用户位于 macOS 环境
- When 执行 `scripts/install_ski.sh --version <version>`
- Then 脚本应下载该版本下对应架构资产
- And 安装完成后 `ski --help` 可执行

### 场景 4：文档可引导终端用户安装

- Given 终端用户阅读项目 README
- When 查找 CLI 使用方式
- Then 可看到“Homebrew 安装”“安装脚本安装”和“源码运行（开发态）”路径

### 场景 5：发布流程生成 Homebrew Formula

- Given 维护者执行 `scripts/release_major.sh release <version> ...`
- When 打包 CLI 资产完成
- Then 发布流程应生成 `dist/homebrew/ski.rb`
- And 该 formula 应引用对应版本的 `ski-macos-arm64.tar.gz` 与 `ski-macos-x86_64.tar.gz`

### 场景 6：同步到独立 Homebrew tap 仓库

- Given 已存在独立 tap 仓库 `linhay/homebrew-tap`
- And 维护者设置 `EXPORT_FORMULA_TO_REPO=1`
- When 执行 release 流程
- Then 生成的 formula 应同步到 tap 仓库的 `Formula/ski.rb`
- And 用户可通过 `brew tap linhay/tap https://github.com/linhay/homebrew-tap && brew install ski` 安装
