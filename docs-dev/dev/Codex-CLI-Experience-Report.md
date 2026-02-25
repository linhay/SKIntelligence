# Codex CLI 体验报告（SKIntelligence）

日期：2026-02-17
范围：`ski acp client connect`、`ski acp serve` 的命令行可用性与可诊断性
方法：`codex exec` 评审 + 本地进程级测试（TDD）

## Round 1
发现：
1. `connect --help` 缺少可直接复制的示例，首次体验成本偏高。
2. `--prompt` 允许全空白输入，错误会在上游链路暴露为连接/运行错误，不利于定位。

改动：
1. 为 `ACPClientConnectCommand` 增加 `discussion` 示例（stdio/ws 各一条）。
2. 增加 `--prompt` 非空白校验，失败走 `invalidInput`（exit code 2）。
3. 新增进程级测试：
   - `testClientConnectHelpContainsExamples`
   - `testClientConnectRejectsEmptyPrompt`

结果：
- 两项用例通过，CLI 首次可发现性与输入校验体验显著提升。

## Round 2
发现：
1. `--permission-message` 参数当前不会进入 ACP 协议负载，用户容易误以为“已生效但服务端未处理”。

改动：
1. 当指定 `--permission-message` 时，输出显式提示：该参数仅信息性用途，不会发送给 ACP server。
2. 新增进程级测试：
   - `testClientPermissionMessageShowsInformationalWarning`

结果：
- 避免“静默无效”造成误判，CLI 行为更可预期。

## 已执行验证
1. `swift test --filter SKICLIProcessTests/testClientConnectRejectsEmptyPrompt --filter SKICLIProcessTests/testClientConnectHelpContainsExamples --filter SKICLIProcessTests/testClientPermissionMessageShowsInformationalWarning`
2. `./scripts/test_acp_gate.sh`（见当前会话输出）

## 下一轮建议
1. 为 `ski acp client connect` 增加 `--session-id`/`--reuse-session`（减少反复 newSession 的体验损耗）。
2. 为 `acp serve` 增加 `--agent-name`/`--agent-version` 覆盖参数，便于联调多实例标识。
3. 在 README 增补最小可运行 CLI 快速路径（stdio 与 ws）。

## Round 3
发现：
1. `--cwd` 非法路径会在上游阶段失败（非输入错误），用户难以定位参数问题。
2. 多个毫秒参数（如 `--request-timeout-ms`）对负值无统一显式拒绝，行为不透明。
3. `--max-in-flight-sends` 传 `0` 会被内部兜底修正，CLI 层缺少明确输入约束反馈。

改动：
1. `client connect` 增加 `--cwd` 目录存在性校验。
2. `client connect` 增加参数校验：
   - `--request-timeout-ms >= 0`
   - `--ws-heartbeat-ms >= 0`
   - `--ws-reconnect-attempts >= 0`
   - `--ws-reconnect-base-delay-ms >= 0`
   - `--max-in-flight-sends > 0`
3. `serve` 增加参数校验：
   - `--prompt-timeout-ms >= 0`
   - `--session-ttl-ms >= 0`
   - `--permission-timeout-ms >= 0`
   - `--max-in-flight-sends > 0`
4. 新增进程级测试：
   - `testClientConnectRejectsInvalidCWD`
   - `testClientConnectRejectsNegativeRequestTimeout`
   - `testServeRejectsInvalidMaxInFlightSends`

结果：
- 参数错误在 CLI 层即以 `exit code 2` 明确反馈，诊断路径更短。
- `./scripts/test_acp_gate.sh` 全通过（188 passed, 1 skipped, 0 failed）。

## Round 4
发现：
1. `--transport ws` 时，`--endpoint` 仅做 URL 可解析校验，未强制 `ws/wss` 协议与 host 存在。
2. `--transport stdio` 时，`--cmd ""` 会延后为运行时失败，而非输入错误。
3. 上述两类输入错误会混入上游失败码（4/5），增加排障成本。

改动：
1. `ACPCLITransportFactory.makeClientTransport` 增加 endpoint 强校验：
   - 必须是 `ws://` 或 `wss://`
   - 必须包含 host
2. `ACPCLITransportFactory.makeClientTransport` 对 stdio `cmd` 增加非空白校验。
3. 新增进程级测试：
   - `testClientRejectsEndpointWithoutWSScheme`
   - `testClientRejectsEndpointWithoutHost`
   - `testClientConnectRejectsEmptyCmdForStdio`

结果：
- 相关输入错误统一在 CLI 层返回 `exit code 2`，不再伪装成上游/内部错误。
- `./scripts/test_acp_gate.sh` 全通过（191 passed, 1 skipped, 0 failed）。
- 备注：`codex exec` 仍出现 `refresh_token_reused` 认证噪音，但不影响本轮本地评审与改动闭环。

## Round 5
发现：
1. `client connect --transport ws` 时允许传入 `--cmd/--args`，但参数会被静默忽略。
2. `client connect --transport stdio` 时允许传入 `--endpoint`，参数语义冲突且会误导排障。
3. `serve --transport stdio` 时允许覆盖 `--listen`，但该参数对 stdio 无效，属于“看起来可配置，实际无效”。

改动：
1. `ACPClientConnectCommand` 增加互斥校验：
   - `ws` 下禁止 `--cmd` / `--args`
   - `stdio` 下禁止 `--endpoint`
2. `ACPServeCommand` 增加互斥校验：
   - `stdio` 下禁止自定义 `--listen`
3. 新增进程级测试：
   - `testClientWSRejectsCmdOption`
   - `testClientStdioRejectsEndpointOption`
   - `testServeStdioRejectsListenOverride`

结果：
- 互斥参数不再被静默吞掉，错误在 CLI 层统一返回 `exit code 2`。
- `./scripts/test_acp_gate.sh` 全通过（194 passed, 1 skipped, 0 failed）。

## Round 6
发现：
1. `client connect --transport stdio` 时，`--ws-heartbeat-ms` 可传但被静默忽略。
2. `client connect --transport stdio` 时，`--ws-reconnect-attempts` 可传但被静默忽略。
3. `client connect --transport stdio` 时，`--ws-reconnect-base-delay-ms` 可传但被静默忽略。

改动：
1. `ACPClientConnectCommand` 增加互斥校验：
   - `stdio` 下禁止覆盖 `--ws-heartbeat-ms`
   - `stdio` 下禁止覆盖 `--ws-reconnect-attempts`
   - `stdio` 下禁止覆盖 `--ws-reconnect-base-delay-ms`
2. 新增进程级测试：
   - `testClientStdioRejectsWSHeartbeatOption`
   - `testClientStdioRejectsWSReconnectAttemptsOption`
   - `testClientStdioRejectsWSReconnectBaseDelayOption`

结果：
- stdio 模式不再接受 ws 专属调参，输入错误统一在 CLI 层返回 `exit code 2`。
- `./scripts/test_acp_gate.sh` 全通过（197 passed, 1 skipped, 0 failed）。

## Round 7
发现：
1. `client connect --transport stdio` 时，`--max-in-flight-sends` 可传但对 stdio 实际无语义，易误导为“生效”。
2. `serve --transport stdio` 时，`--max-in-flight-sends` 同样属于 ws 专属参数，当前允许覆盖存在静默无效风险。

改动：
1. `ACPClientConnectCommand` 增加互斥校验：
   - `stdio` 下禁止覆盖 `--max-in-flight-sends`（必须保持默认值 64）。
2. `ACPServeCommand` 增加互斥校验：
   - `stdio` 下禁止覆盖 `--max-in-flight-sends`（必须保持默认值 64）。
3. 新增/调整进程级测试：
   - `testClientStdioRejectsMaxInFlightSendsOption`
   - `testServeStdioRejectsMaxInFlightSendsOverride`
   - `testServeRejectsInvalidMaxInFlightSends`（改为 ws 场景验证 `> 0`）

结果：
- stdio 下 ws 专属发送背压参数不再被静默接受，CLI 语义与 transport 能力对齐。
- `./scripts/test_acp_gate.sh` 全通过（199 passed, 1 skipped, 0 failed）。

## Round 8
发现：
1. `stdio` 下 ws 专属参数采用“值是否偏离默认值”判定，导致显式传入默认值时被静默接受（例如 `--ws-heartbeat-ms 15000`）。
2. `serve stdio` 的 `--listen` 与 `--max-in-flight-sends` 同样存在默认值绕过。
3. `client connect --transport ws` 仍强制本地 `--cwd` 目录存在，阻断远端有效路径场景。

改动：
1. 在 `ACPClientConnectCommand` 与 `ACPServeCommand` 增加显式传参检测（扫描 `CommandLine.arguments`）：
   - `stdio` 下只要显式出现 ws 专属参数即报错，不再依赖默认值比较。
2. `client connect` 的 `--cwd` 本地存在性校验改为仅在 `transport == stdio` 时生效。
3. 新增进程级测试：
   - `testClientStdioRejectsWSHeartbeatOptionEvenWhenDefaultProvided`
   - `testServeStdioRejectsListenOptionEvenWhenDefaultProvided`
   - `testServeStdioRejectsMaxInFlightSendsOptionEvenWhenDefaultProvided`
   - `testClientWSDoesNotRequireLocalCWDExistence`

结果：
- 消除了“显式传参但静默无效”的默认值绕过漏洞。
- ws 模式 `cwd` 行为更贴近远端语义，不再被本地路径预检误拦截。
- `./scripts/test_acp_gate.sh` 全通过（203 passed, 1 skipped, 0 failed）。

## Round 9
发现：
1. `stdio` 下若传入 ws 专属参数的非法值（如 `--ws-heartbeat-ms=-1`），当前会先报“范围错误”，而不是先报“该参数不适用于 stdio”，修复方向不够直观。
2. `--args` 传递 option-like token（如 `--transport`）时容易被父命令重解释，现有报错缺少明确迁移提示。

改动：
1. 调整 `ACPClientConnectCommand` 校验顺序：
   - 先做 transport 适用性校验（`stdio` 下拒绝 ws 专属参数）。
   - 再做数值范围校验（`>= 0` / `> 0`）。
2. 在 `transport == ws && cmd != nil && 显式传了 --args` 场景输出增强提示：
   - 提示 option-like child args 使用 `--args=--flag` 形式，避免被父命令解析。
3. 新增进程级测试：
   - `testClientStdioWsOnlyOptionPrioritizesTransportScopeErrorOverRangeError`
   - `testClientArgsOptionLikeTokenShowsHint`

结果：
- stdio 下 ws 参数错误优先级更合理，用户更快定位“参数作用域错误”。
- `--args` 误解析场景下提供了可执行修复提示，降低排障成本。
- `./scripts/test_acp_gate.sh` 全通过（205 passed, 1 skipped, 0 failed）。

## Round 10
发现：
1. `--args` 仍使用 `.upToNextOption`，但 help 示例未明确“子参数若以 `-` 开头需要 `--args=...`”这一规则，容易误用。
2. `--permission-message` 运行时会提示“仅本地信息，不发给服务端”，但 `--help` 描述不够直观。

改动：
1. 更新 `client connect` 的 `discussion` 示例：
   - stdio 示例改为 `--args acp --args serve --args=--transport --args=stdio`。
   - 新增 `Note` 明确 `--args=--flag` 规则。
2. 更新 `--permission-message` 参数帮助文案为：
   - `Informational only. Printed locally; not sent to ACP server`
3. 新增进程级测试：
   - `testClientConnectHelpExamplesUseArgsEqualsForOptionLikeChildArgs`
   - `testClientConnectHelpMarksPermissionMessageAsInformationalOnly`

结果：
- CLI `--help` 与真实行为一致，减少参数误用与理解偏差。
- `./scripts/test_acp_gate.sh` 全通过（207 passed, 1 skipped, 0 failed）。

## Round 11
发现：
1. `serve --permission-mode disabled` 时仍可显式传 `--permission-timeout-ms`，参数语义冲突。
2. `client connect --cwd` 在 ws 场景下的“路径属于服务端”语义不够直观，容易被理解为本地路径。

改动：
1. `ACPServeCommand` 增加校验：`permission-mode=disabled` 下显式传 `--permission-timeout-ms` 直接报 `invalidInput`。
2. `ACPClientConnectCommand` 更新 `--cwd` 帮助文案，明确 ws 下应传服务端可识别路径。
3. 新增进程级测试：
   - `testServePermissionTimeoutOptionRejectedWhenPermissionModeDisabled`
   - `testClientConnectHelpMentionsCWDIsSentToServer`

结果：
- 参数约束和帮助文案语义保持一致，避免“可传但无意义”输入。
- `./scripts/test_acp_gate.sh` 全通过（209 passed, 1 skipped, 0 failed）。

## Round 12
发现：
1. `acp client connect` 把 stdio/ws 参数混放在同一命令，虽有大量互斥校验，但学习成本高。
2. 体验上更自然的路径是 transport 级子命令，避免“先输入再被拒绝”的使用方式。

改动：
1. 新增子命令：
   - `ski acp client connect-stdio`
   - `ski acp client connect-ws`
2. 抽取共享执行逻辑 `runACPClientConnect(...)`，避免重复实现和行为漂移。
3. 新增进程级测试：
   - `testClientConnectStdioHelpHidesWSOnlyOptions`
   - `testClientConnectWSHelpHidesStdioOnlyOptions`

结果：
- transport 参数在帮助层面先行分流，显著降低参数误配概率。
- 全量 `SKICLIProcessTests` 通过，`./scripts/test_acp_gate.sh` 全通过（211 passed, 1 skipped, 0 failed）。

## Round 13
发现：
1. `--json` 下 `session_update` 事件有 `type`，但最终结果行缺少 `type`，NDJSON 事件模型不统一。
2. 脚本消费时需要对“最后一行特殊处理”，增加解析复杂度与出错概率。

改动：
1. `ACPCLIOutputFormatter.promptResultJSON` 增加 `type: "prompt_result"` 字段。
2. 新增测试：
   - `SKICLITests.testPromptResultJSONPayloadShape` 增加 `type` 断言。
   - `SKICLIProcessTests.testClientConnectViaStdioServeProcessJSONEmitsPromptResultType` 校验真实进程输出最后一行为 `prompt_result`。

结果：
- `--json` 输出事件类型统一，脚本可按 `type` 一致分发处理。
- `swift test --filter SKICLITests/testPromptResultJSONPayloadShape --filter SKICLIProcessTests/testClientConnectViaStdioServeProcessJSONEmitsPromptResultType` 通过。
- 全量 `SKICLIProcessTests` 通过，`./scripts/test_acp_gate.sh` 全通过（212 passed, 1 skipped, 0 failed）。

## Round 14
发现：
1. `--request-timeout-ms 0` 当前会立即触发超时（如 `initialize`），与用户直觉冲突。
2. `connect-stdio/connect-ws/connect` 的 `--help` 未明确 `0` 的语义，存在使用歧义。

改动：
1. 统一 `--request-timeout-ms` 语义：
   - `0` 表示禁用超时（不设置请求超时）。
   - 默认值调整为 `60000` ms。
2. 更新 `connect-stdio/connect-ws/connect` 的帮助文案为：
   - `Request timeout in milliseconds (0 disables)`。
3. 新增进程级测试：
   - `testClientConnectStdioHelpMentionsRequestTimeoutZeroDisables`
   - `testClientConnectWSHelpMentionsRequestTimeoutZeroDisables`
   - `testClientConnectViaStdioServeProcessTimeoutZeroDisablesTimeout`

结果：
- `--request-timeout-ms` 行为与文案一致，避免“0 导致立即失败”的体验陷阱。
- 定向测试通过，`SKICLIProcessTests` 全通过（37 passed, 0 failed）。
- `./scripts/test_acp_gate.sh` 全通过（215 passed, 1 skipped, 0 failed）。

## Round 15
发现：
1. `connect/connect-stdio/connect-ws` 仍不支持显式复用会话，只能每次 `session/new`。
2. CLI 缺少 `--session-id` 参数，无法把外部持有的会话 ID 串到下一次调用。

改动：
1. 为 `connect/connect-stdio/connect-ws` 增加 `--session-id`：
   - 帮助文案：`Reuse an existing ACP session ID instead of creating a new one`。
2. 新增参数校验：
   - 显式传入空白 `--session-id` 时返回 `invalidInput`（exit code 2）。
3. 复用逻辑落地：
   - 传 `--session-id` 时跳过 `session/new`，直接对该会话调用 `session/prompt`；
   - 未传时保持原行为（自动 `session/new`）。
4. 新增进程级测试：
   - `testClientConnectRejectsEmptySessionID`
   - `testClientConnectViaStdioWithNonexistentSessionIDFails`
   - 同时扩展 help 断言覆盖 `--session-id` 可发现性。

结果：
- 会话复用路径落地，CLI 支持显式绑定会话 ID。
- 定向测试通过；`SKICLIProcessTests` 全通过（39 passed, 0 failed）。
- `./scripts/test_acp_gate.sh` 全通过（217 passed, 1 skipped, 0 failed）。

## Round 16
发现：
1. 真实体验 `connect-stdio` 时，若 `--cmd` 传命令名（如 `env`/`swift`）会在运行期失败：`The file “xxx” doesn’t exist.`。
2. 当前行为隐含“必须绝对路径”，与终端 CLI 习惯不一致，影响首用成功率。

改动：
1. 在 `ACPCLITransportFactory` 为 stdio `--cmd` 增加命令解析：
   - 若包含 `/`：按路径校验可执行性；
   - 若不含 `/`：按 `PATH` 搜索并解析为绝对可执行路径。
2. 对未知命令前置返回 `invalidInput`：
   - 错误文案：`--cmd was not found in PATH for stdio transport`。
3. 新增/更新测试：
   - `SKICLITests.testACPClientConnectResolvesCommandFromPATHForStdio`
   - `SKICLITests.testACPClientConnectRejectsUnknownCommandForStdio`
   - `SKICLIProcessTests.testClientConnectViaStdioResolvesCmdFromPATH`
4. 更新 BDD 规格：
   - `docs-dev/features/CLI-Benchmark-Spec.md` 增加“stdio 子进程命令支持 PATH 解析”场景。

结果：
- 定向红绿测试通过（3 条）。
- `SKICLIProcessTests` 全通过（40 passed, 0 failed）。
- `./scripts/test_acp_gate.sh` 全通过（220 passed, 1 skipped, 0 failed）。

## Round 17
发现：
1. 经过 Round 16 后，`--cmd swift` 已可正常工作，但 `connect-stdio --help` 对 `--cmd` 仍无语义说明，用户无法从帮助文案得知“可传 PATH 命令名”。
2. `codex exec --json` 在本机会伴随 MCP/rollout 噪音日志（`IncompleteMessage` / `state db missing rollout path`），不阻塞执行，但会干扰体验判读。

改动：
1. 为 `connect-stdio` 与 `connect` 的 `--cmd` 增加帮助文案：
   - `Child executable path or command name in PATH`。
2. 新增进程级帮助测试：
   - `SKICLIProcessTests.testClientConnectStdioHelpMentionsCmdCanUsePATH`
3. 更新 BDD 规格：
   - `docs-dev/features/CLI-Benchmark-Spec.md` 增加 “help 明确 --cmd 的 PATH 语义” 场景。

结果：
- 定向测试通过（help + PATH 解析相关）。
- `SKICLIProcessTests` 全通过（41 passed, 0 failed）。
- `./scripts/test_acp_gate.sh` 全通过（221 passed, 1 skipped, 0 failed）。

## Round 18
发现：
1. `connect-stdio` 中若误写为 `--args --transport`，CLI 会返回 `Missing value for '--args <args>'`，但 `connect-stdio --help` 未明确 `--args=--flag` 规则，修复路径不直观。
2. 虽然 `connect` 已有该提示，但 transport 子命令的帮助信息不对齐，首用用户更容易在 `connect-stdio` 上踩坑。

改动：
1. 为 `connect-stdio` 补充 `discussion`：
   - 示例：`--args=--transport --args=stdio`
   - Note：子参数以 `-` 开头时使用 `--args=--flag`。
2. 新增进程级测试：
   - `SKICLIProcessTests.testClientConnectStdioHelpMentionsArgsEqualsForOptionLikeChildArgs`
3. 更新 BDD 规格：
   - `docs-dev/features/CLI-Benchmark-Spec.md` 增加 “help 说明 --args 的 option-like 传参规则” 场景。

结果：
- 定向测试通过（help + stdio PATH 回归）。
- `SKICLIProcessTests` 全通过（42 passed, 0 failed）。
- `./scripts/test_acp_gate.sh` 全通过（222 passed, 1 skipped, 0 failed）。
