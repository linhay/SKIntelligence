# STJSON JSON-RPC 迁移规格（BDD）

## 背景
将 SKIntelligence 的 JSON-RPC 协议层从自研实现迁移到 STJSON 1.4.9，要求保持 ACP 现有业务行为不回退。

## 场景 1：请求/通知/响应编解码保持兼容
- Given 现有 ACP 使用的 request/notification/response 数据
- When 通过迁移后的 codec 编解码
- Then 行为与迁移前一致，且能与 STJSON JSONRPC 严格规则对齐

## 场景 2：严格 JSON-RPC 2.0 规则
- Given 非法 version/非法 envelope/非法 result-error 组合
- When 解码
- Then 返回明确错误（invalidVersion 或 invalidEnvelope）

## 场景 3：stdio 与 websocket transport 无回归
- Given ACP stdio/ws 运行时
- When 进行 prompt/cancel/session 路由
- Then 端到端行为与原有测试矩阵一致

## 场景 4：client/service/agent 语义保持
- Given 现有 ACPClientService 与 ACPAgentService 调用流
- When 在迁移后执行
- Then timeout、cancel、permission、session 生命周期语义不变

## 场景 5：依赖升级与模块收敛
- Given 包依赖配置
- When 迁移完成
- Then STJSON 升级到 1.4.9 且移除 SKIJSONRPC 目标与源码目录

## 验收标准
- `JSONRPCCodecTests` 全部通过。
- `ACPAgentServiceTests` / `ACPClientServiceTests` / `ACPDomainE2EMatrixTests` / transport 相关测试通过。
- 全量 `swift test` 中与本次迁移直接相关测试通过；若有既有不稳定/外部依赖测试失败，需明确记录。
