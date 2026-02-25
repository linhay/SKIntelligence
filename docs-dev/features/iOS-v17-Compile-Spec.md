# iOS v17 编译兼容规格（临时任务）

## 背景
- 目标：保证 `Package.swift` 声明的 `.iOS(.v17)` 可以成功编译。
- 现状阻塞：`SKProcessRunner` 的 PTY 能力依赖 iOS 不可用 API（如 `posix_spawn_file_actions_addchdir_np`）。

## BDD 场景
1. 场景：iOS 17 编译不再被 Shell Runtime 阻塞
- Given 工程平台声明包含 `.iOS(.v17)`
- When 执行 iOS Simulator 构建
- Then 不应因 `SKProcessRunner` 的 iOS 不可用 API 失败

2. 场景：不支持平台下能力降级明确
- Given 当前平台不支持 `SKProcessRunner`
- When 调用 `SKIToolShell`
- Then 返回 `toolUnavailable`，并包含明确原因

3. 场景：macOS 行为保持
- Given 在 macOS 平台调用 `SKIToolShell`
- When 平台支持 `SKProcessRunner`
- Then `isRuntimeSupported == true`，且原有调用路径不变
