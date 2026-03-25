# MLX E2E Runbook

## 目标

在本机稳定运行 `MLXClientDeterminismE2ETests`（真实模型、同 seed 输出一致性）。

## 前提

1. macOS + Xcode 命令行工具可用。
2. 已完成依赖解析（`swift package resolve`）。
3. 可访问 Hugging Face 模型仓库（首次会下载模型）。

## 推荐流程（一键）

```bash
scripts/mlx_e2e_prepare.sh --run --model-id mlx-community/Qwen2.5-0.5B-4bit --timeout-seconds 120 --temperature 0
```

说明：
1. 脚本会自动检查 `default.metallib`。
2. 缺失时会调用 `xcodebuild` 构建 `mlx-swift` 的 `Cmlx` 产物。
3. 自动复制 `default.metallib` 到仓库根目录。
4. 自动执行 E2E 测试。

## 分步流程

1. 仅准备 metallib：

```bash
scripts/mlx_e2e_prepare.sh --model-id mlx-community/Qwen2.5-0.5B-4bit
```

2. 手动运行 E2E：

```bash
RUN_MLX_E2E_TESTS=1 \
MLX_E2E_MODEL_ID='mlx-community/Qwen2.5-0.5B-4bit' \
MLX_E2E_REQUEST_TIMEOUT_SECONDS=120 \
MLX_E2E_TEMPERATURE=0 \
swift test --filter MLXClientDeterminismE2ETests
```

3. 运行 VLM 图片识别 E2E（Qwen VL）：

```bash
RUN_MLX_E2E_VL_TESTS=1 \
MLX_E2E_MODEL_ID='mlx-community/Qwen2-VL-2B-Instruct-4bit' \
MLX_E2E_REQUEST_TIMEOUT_SECONDS=240 \
MLX_E2E_TEMPERATURE=0 \
MLX_E2E_VL_IMAGE_URL='file:///tmp/mlx_vl_test.png' \
swift test --filter MLXClientDeterminismE2ETests/testQwenVLCanDescribeImageFromURL
```

说明：
1. `MLX_E2E_VL_IMAGE_URL` 建议优先使用 `file://` 本地路径，避免远程 URL 加载不确定性。
2. 测试会输出 `MLX_E2E_VL_OUTPUT: ...` 便于快速核对识别结果。

## 常见问题

1. `Failed to load the default metallib`
   - 原因：缺少 Metal shader 产物。
   - 处理：执行 `scripts/mlx_e2e_prepare.sh --model-id <model-id>`。

2. E2E 直接 skip（找不到 `*.metallib`）
   - 原因：运行时路径内无 metallib。
   - 处理：
     - 确认仓库根目录有 `default.metallib`；
     - 或设置 `MLX_E2E_METALLIB_DIR=<目录>` 指向含 `*.metallib` 的路径。

3. determinism 断言失败（同 seed 输出不一致）
   - 处理建议：
     - 设 `MLX_E2E_TEMPERATURE=0`；
     - 固定模型 revision（`MLX_E2E_MODEL_REVISION`）；
     - 保持 prompt 不变并适当增大超时。

4. `unsupportedModelType("qwen2_vl")`
   - 原因：未链接 `MLXVLM`，导致 VLM 工厂未注册。
   - 处理：确认 `SKIMLXClient` target 依赖包含 `MLXVLM`，并重新构建。

## 备注

1. `default.metallib` 已加入 `.gitignore`，不会纳入版本控制。
2. 若本地 DerivedData 被清理，重新执行脚本即可恢复运行环境。
