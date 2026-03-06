# CLI 安装与分发 Runbook

## 适用范围

- 面向 `ski` CLI 的终端用户安装分发。
- 覆盖发布资产产出、上传与安装脚本使用。

## 发布资产约定

发布后应在 GitHub Release 中看到：

1. `ski-macos-arm64.tar.gz`
2. `ski-macos-arm64.sha256`
3. `ski-macos-x86_64.tar.gz`
4. `ski-macos-x86_64.sha256`
5. `skintelligence.skill`（现有技能包资产）
6. `ski.rb`（Homebrew Formula 资产）

## 发布命令

```bash
DRY_RUN=0 RUN_PACKAGE_CLI=1 scripts/release_major.sh release <version> <notes_file>
```

说明：

1. `release_major.sh` 会调用 `scripts/package_cli.sh --arch all --output-dir dist/cli`。
2. `dist/cli` 下生成的 `ski-macos-*` 资产会自动附加到 GitHub Release。
3. 默认会调用 `scripts/generate_homebrew_formula.sh` 生成 `dist/homebrew/ski.rb`，并附加到 GitHub Release。
4. 当 `EXPORT_FORMULA_TO_REPO=1` 时，会调用 `scripts/sync_homebrew_tap.sh` 将 formula 同步到 `linhay/homebrew-tap` 的 `Formula/ski.rb`。

## 本地手动打包

```bash
scripts/package_cli.sh --arch all --output-dir dist/cli
```

## Homebrew Formula 生成

```bash
scripts/generate_homebrew_formula.sh --version <version> --sha-dir dist/cli --output dist/homebrew/ski.rb
```

## 用户安装

```bash
curl -fsSL https://raw.githubusercontent.com/linhay/SKIntelligence/main/scripts/install_ski.sh | bash
```

或固定版本：

```bash
curl -fsSL https://raw.githubusercontent.com/linhay/SKIntelligence/main/scripts/install_ski.sh | bash -s -- --version <version>
```

## 用户安装（Homebrew）

```bash
brew tap linhay/tap https://github.com/linhay/homebrew-tap
brew install linhay/tap/ski
```

按发布版本直装（无需 tap）：

```bash
brew install --formula https://github.com/linhay/SKIntelligence/releases/download/<version>/ski.rb
```

## 安装后验证

```bash
ski --help
ski --version
ski acp serve --help
ski acp client --help
```

预期：

1. `ski` 显示 help，不进入交互聊天页。
2. help 中包含 `acp`，不包含 `tui`。
3. `ski --version` 返回已安装版本。
