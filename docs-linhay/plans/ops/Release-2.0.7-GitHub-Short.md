# Release 2.0.7 (GitHub Short)

## Summary

- 升级 `swift-json-schema` 到 `0.11.2`。
- 移除顶层显式 `swift-syntax` 依赖声明，改为由上游依赖按需传递解析。

## Changes

1. 依赖升级
   - `Package.swift`:
     - `https://github.com/ajevans99/swift-json-schema` 从 `0.11.0` 升级到 `0.11.2`
2. 依赖声明收敛
   - `Package.swift`:
     - 移除 `.package(url: "https://github.com/swiftlang/swift-syntax", from: "602.0.0")`
3. 锁文件更新
   - `Package.resolved`:
     - `swift-json-schema` 解析到 `0.11.2`

## Validation

- 依赖解析：`swift package resolve`
- 构建验证：`swift build -c debug`

## Upgrade Notes

1. `swift-syntax` 仍可能出现在 `Package.resolved` 中，这是传递依赖行为，非顶层显式依赖。
2. 本次变更不涉及 API 破坏性调整，仅为依赖版本与声明策略调整。
