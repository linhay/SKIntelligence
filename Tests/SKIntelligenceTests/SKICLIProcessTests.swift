import Foundation
import XCTest

final class SKICLIProcessTests: XCTestCase {
    func testClientConnectRejectsEmptyPrompt() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--args", "cat",
            "--prompt", "   "
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--prompt must not be empty"))
    }

    func testClientConnectRejectsMissingPrompt() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--args", "cat"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--prompt must be provided at least once"))
    }

    func testClientConnectStdioRejectsMissingPrompt() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect-stdio",
            "--cmd", "/usr/bin/env",
            "--args", "cat"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--prompt must be provided at least once"))
    }

    func testClientConnectWSRejectsMissingPrompt() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect-ws",
            "--endpoint", "ws://127.0.0.1:1"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--prompt must be provided at least once"))
    }

    func testClientConnectStdioRejectsMissingCmd() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect-stdio",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--cmd is required for stdio transport"))
    }

    func testClientConnectWSRejectsMissingEndpoint() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect-ws",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--endpoint is required for ws transport"))
    }

    func testClientStopRejectsMissingSessionID() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "stop",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--args", "cat"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--session-id is required"))
    }

    func testClientStopRejectsEmptySessionID() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "stop",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--args", "cat",
            "--session-id", "   "
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--session-id must not be empty"))
    }

    func testClientConnectStdioRejectsNegativeRequestTimeout() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect-stdio",
            "--cmd", "/usr/bin/env",
            "--args", "cat",
            "--request-timeout-ms=-1",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--request-timeout-ms must be >= 0"))
    }

    func testClientConnectWSRejectsNegativeRequestTimeout() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect-ws",
            "--endpoint", "ws://127.0.0.1:1",
            "--request-timeout-ms=-1",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--request-timeout-ms must be >= 0"))
    }

    func testClientConnectWSRejectsNegativeHeartbeat() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect-ws",
            "--endpoint", "ws://127.0.0.1:1",
            "--ws-heartbeat-ms=-1",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--ws-heartbeat-ms must be >= 0"))
    }

    func testClientConnectWSRejectsNegativeReconnectAttempts() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect-ws",
            "--endpoint", "ws://127.0.0.1:1",
            "--ws-reconnect-attempts=-1",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--ws-reconnect-attempts must be >= 0"))
    }

    func testClientConnectWSRejectsNegativeReconnectBaseDelay() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect-ws",
            "--endpoint", "ws://127.0.0.1:1",
            "--ws-reconnect-base-delay-ms=-1",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--ws-reconnect-base-delay-ms must be >= 0"))
    }

    func testClientConnectWSRejectsNonPositiveMaxInFlightSends() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect-ws",
            "--endpoint", "ws://127.0.0.1:1",
            "--max-in-flight-sends=0",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--max-in-flight-sends must be > 0"))
    }

    func testClientConnectHelpContainsExamples() throws {
        let result = try runSKI(arguments: ["acp", "client", "connect", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Examples:"))
        XCTAssertTrue(result.stdout.contains("ski acp client connect --transport stdio"))
        XCTAssertTrue(result.stdout.contains("ski acp client connect --transport ws --endpoint"))
    }

    func testClientHelpContainsStopSubcommand() throws {
        let result = try runSKI(arguments: ["acp", "client", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("stop"))
    }

    func testClientConnectStdioHelpHidesWSOnlyOptions() throws {
        let result = try runSKI(arguments: ["acp", "client", "connect-stdio", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("--cmd"))
        XCTAssertTrue(result.stdout.contains("--args"))
        XCTAssertFalse(result.stdout.contains("--endpoint"))
        XCTAssertFalse(result.stdout.contains("--ws-heartbeat-ms"))
        XCTAssertFalse(result.stdout.contains("--ws-reconnect-attempts"))
    }

    func testClientConnectWSHelpHidesStdioOnlyOptions() throws {
        let result = try runSKI(arguments: ["acp", "client", "connect-ws", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("--endpoint"))
        XCTAssertTrue(result.stdout.contains("--ws-heartbeat-ms"))
        XCTAssertFalse(result.stdout.contains("--cmd"))
        XCTAssertFalse(result.stdout.contains("--args"))
    }

    func testClientStopStdioHelpHidesWSOnlyOptions() throws {
        let result = try runSKI(arguments: ["acp", "client", "stop-stdio", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("--cmd"))
        XCTAssertTrue(result.stdout.contains("--args"))
        XCTAssertTrue(result.stdout.contains("--session-id"))
        XCTAssertFalse(result.stdout.contains("--endpoint"))
        XCTAssertFalse(result.stdout.contains("--ws-heartbeat-ms"))
    }

    func testClientStopWSHelpHidesStdioOnlyOptions() throws {
        let result = try runSKI(arguments: ["acp", "client", "stop-ws", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("--endpoint"))
        XCTAssertTrue(result.stdout.contains("--session-id"))
        XCTAssertFalse(result.stdout.contains("--cmd"))
        XCTAssertFalse(result.stdout.contains("--args"))
    }

    func testClientConnectStdioHelpMentionsRequestTimeoutZeroDisables() throws {
        let result = try runSKI(arguments: ["acp", "client", "connect-stdio", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("0 disables"))
        XCTAssertTrue(result.stdout.contains("--session-id"))
    }

    func testClientConnectStdioHelpMentionsCmdCanUsePATH() throws {
        let result = try runSKI(arguments: ["acp", "client", "connect-stdio", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("PATH"), "stdout: \(result.stdout)")
    }

    func testClientConnectStdioHelpMentionsArgsEqualsForOptionLikeChildArgs() throws {
        let result = try runSKI(arguments: ["acp", "client", "connect-stdio", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("--args=--transport"), "stdout: \(result.stdout)")
    }

    func testClientConnectWSHelpMentionsRequestTimeoutZeroDisables() throws {
        let result = try runSKI(arguments: ["acp", "client", "connect-ws", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("0 disables"))
        XCTAssertTrue(result.stdout.contains("--session-id"))
    }

    func testClientConnectHelpExamplesUseArgsEqualsForOptionLikeChildArgs() throws {
        let result = try runSKI(arguments: ["acp", "client", "connect", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("--args=--transport"))
    }

    func testClientConnectHelpMarksPermissionMessageAsInformationalOnly() throws {
        let result = try runSKI(arguments: ["acp", "client", "connect", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Informational only."))
    }

    func testServeHelpContainsTimeoutAndTTLParameters() throws {
        let result = try runSKI(arguments: ["acp", "serve", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("--prompt-timeout-ms"))
        XCTAssertTrue(result.stdout.contains("--session-ttl-ms"))
        XCTAssertTrue(result.stdout.contains("--permission-timeout-ms"))
    }

    func testServeHelpMentionsPermissionModeValues() throws {
        let result = try runSKI(arguments: ["acp", "serve", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("disabled | permissive | required"))
    }

    func testServeHelpContainsWSListenAndBackpressureOptions() throws {
        let result = try runSKI(arguments: ["acp", "serve", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("--listen"))
        XCTAssertTrue(result.stdout.contains("--max-in-flight-sends"))
    }

    func testClientConnectHelpMentionsCWDIsSentToServer() throws {
        let result = try runSKI(arguments: ["acp", "client", "connect", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("sent to session/new"))
    }

    func testClientMissingEndpointExitCodeIs2() throws {
        let result = try runSKI(arguments: ["acp", "client", "connect", "--transport", "ws", "--prompt", "hi"])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--endpoint is required for ws transport"))
    }

    func testClientRejectsEndpointWithoutWSScheme() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "ws",
            "--endpoint", "http://127.0.0.1:8900",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--endpoint must use ws:// or wss:// and include host"))
    }

    func testClientRejectsEndpointWithoutHost() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "ws",
            "--endpoint", "ws:///path-only",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--endpoint must use ws:// or wss:// and include host"))
    }

    func testClientConnectWSRejectsEndpointWithoutWSScheme() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect-ws",
            "--endpoint", "http://127.0.0.1:8900",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--endpoint must use ws:// or wss:// and include host"))
    }

    func testClientConnectWSRejectsEndpointWithoutHost() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect-ws",
            "--endpoint", "ws:///path-only",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--endpoint must use ws:// or wss:// and include host"))
    }

    func testClientWSRejectsCmdOption() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "ws",
            "--endpoint", "ws://127.0.0.1:8900",
            "--cmd", "/usr/bin/env",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--cmd is only valid for stdio transport"))
    }

    func testClientWSRejectsArgsOption() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "ws",
            "--endpoint", "ws://127.0.0.1:8900",
            "--args", "serve",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--args is only valid for stdio transport"))
    }

    func testClientWSCmdWithArgsShowsArgsEqualsHint() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "ws",
            "--endpoint", "ws://127.0.0.1:8900",
            "--cmd", "/usr/bin/env",
            "--args=--transport",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--cmd is only valid for stdio transport (if child args start with '-', pass as --args=--flag)"))
        XCTAssertTrue(result.stderr.contains("--args=--flag"))
    }

    func testClientArgsOptionLikeTokenShowsHint() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--args", "acp", "serve",
            "--transport", "ws",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--args=--flag"))
    }

    func testClientUpstreamFailureExitCodeIs4() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "ws",
            "--endpoint", "ws://127.0.0.1:1",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 4)
        XCTAssertTrue(result.stderr.contains("Error:"), "stderr did not contain error summary: \(result.stderr)")
        XCTAssertFalse(
            result.stderr.contains("--endpoint is required for ws transport"),
            "stderr unexpectedly looked like validation error: \(result.stderr)"
        )
    }

    func testClientPermissionMessageShowsInformationalWarning() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "ws",
            "--endpoint", "ws://127.0.0.1:1",
            "--permission-message", "manual-note",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 4)
        XCTAssertTrue(result.stderr.contains("Warning: --permission-message is informational only"))
    }

    func testClientConnectRejectsInvalidCWD() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--args", "cat",
            "--cwd", "/path/that/does/not/exist",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--cwd must be an existing directory"))
    }

    func testClientWSDoesNotRequireLocalCWDExistence() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "ws",
            "--endpoint", "ws://127.0.0.1:1",
            "--cwd", "/path/only-exists-on-server",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 4)
        XCTAssertFalse(result.stderr.contains("--cwd must be an existing directory"))
    }

    func testClientConnectRejectsNegativeRequestTimeout() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--args", "cat",
            "--request-timeout-ms=-1",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--request-timeout-ms must be >= 0"))
    }

    func testClientConnectGenericWSRejectsNegativeHeartbeat() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "ws",
            "--endpoint", "ws://127.0.0.1:1",
            "--ws-heartbeat-ms=-1",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--ws-heartbeat-ms must be >= 0"))
    }

    func testClientConnectGenericWSRejectsNegativeReconnectAttempts() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "ws",
            "--endpoint", "ws://127.0.0.1:1",
            "--ws-reconnect-attempts=-1",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--ws-reconnect-attempts must be >= 0"))
    }

    func testClientConnectGenericWSRejectsNegativeReconnectBaseDelay() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "ws",
            "--endpoint", "ws://127.0.0.1:1",
            "--ws-reconnect-base-delay-ms=-1",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--ws-reconnect-base-delay-ms must be >= 0"))
    }

    func testClientConnectGenericWSRejectsNonPositiveMaxInFlightSends() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "ws",
            "--endpoint", "ws://127.0.0.1:1",
            "--max-in-flight-sends=0",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--max-in-flight-sends must be > 0"))
    }

    func testClientConnectRejectsEmptySessionID() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect-stdio",
            "--cmd", "/usr/bin/env",
            "--args", "cat",
            "--session-id", "   ",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--session-id must not be empty when provided"))
    }

    func testClientConnectWSRejectsEmptySessionID() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect-ws",
            "--endpoint", "ws://127.0.0.1:1",
            "--session-id", "   ",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--session-id must not be empty when provided"))
    }

    func testClientConnectGenericWSRejectsEmptySessionID() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "ws",
            "--endpoint", "ws://127.0.0.1:1",
            "--session-id", "   ",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--session-id must not be empty when provided"))
    }

    func testClientConnectRejectsEmptyCmdForStdio() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--cmd must not be empty for stdio transport"))
    }

    func testServeInvalidListenExitCodeIs2() throws {
        let result = try runSKI(arguments: ["acp", "serve", "--transport", "ws", "--listen", "invalid"])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--listen must be in host:port format with port in 1...65535"))
    }

    func testServeRejectsNegativePromptTimeout() throws {
        let result = try runSKI(arguments: [
            "acp", "serve",
            "--transport", "stdio",
            "--prompt-timeout-ms=-1"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--prompt-timeout-ms must be >= 0"))
    }

    func testServeRejectsNegativeSessionTTL() throws {
        let result = try runSKI(arguments: [
            "acp", "serve",
            "--transport", "stdio",
            "--session-ttl-ms=-1"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--session-ttl-ms must be >= 0"))
    }

    func testServeRejectsNegativePermissionTimeoutWhenModeEnabled() throws {
        let result = try runSKI(arguments: [
            "acp", "serve",
            "--transport", "stdio",
            "--permission-mode", "permissive",
            "--permission-timeout-ms=-1"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--permission-timeout-ms must be >= 0"))
    }

    func testServePermissionTimeoutOptionRejectedWhenPermissionModeDisabled() throws {
        let result = try runSKI(arguments: [
            "acp", "serve",
            "--transport", "stdio",
            "--permission-mode", "disabled",
            "--permission-timeout-ms", "1"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--permission-timeout-ms is only valid when --permission-mode is permissive or required"))
    }

    func testServeWSPermissionTimeoutOptionRejectedWhenPermissionModeDisabled() throws {
        let result = try runSKI(arguments: [
            "acp", "serve",
            "--transport", "ws",
            "--listen", "127.0.0.1:8900",
            "--permission-mode", "disabled",
            "--permission-timeout-ms", "1"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--permission-timeout-ms is only valid when --permission-mode is permissive or required"))
    }

    func testServeWSPermissionTimeoutScopeErrorOverridesRangeErrorWhenDisabled() throws {
        let result = try runSKI(arguments: [
            "acp", "serve",
            "--transport", "ws",
            "--listen", "127.0.0.1:8900",
            "--permission-mode", "disabled",
            "--permission-timeout-ms=-1"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--permission-timeout-ms is only valid when --permission-mode is permissive or required"))
        XCTAssertFalse(result.stderr.contains("--permission-timeout-ms must be >= 0"))
    }

    func testServePermissionTimeoutScopeErrorOverridesRangeErrorWhenDisabled() throws {
        let result = try runSKI(arguments: [
            "acp", "serve",
            "--transport", "stdio",
            "--permission-mode", "disabled",
            "--permission-timeout-ms=-1"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--permission-timeout-ms is only valid when --permission-mode is permissive or required"))
        XCTAssertFalse(result.stderr.contains("--permission-timeout-ms must be >= 0"))
    }

    func testClientStdioRejectsEndpointOption() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--endpoint", "ws://127.0.0.1:8900",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--endpoint is only valid for ws transport"))
    }

    func testClientStdioEndpointScopeErrorOverridesEndpointFormatError() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--endpoint", "invalid",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--endpoint is only valid for ws transport"))
        XCTAssertFalse(result.stderr.contains("--endpoint must use ws:// or wss://"))
    }

    func testClientStdioRejectsWSHeartbeatOption() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--ws-heartbeat-ms", "12000",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--ws-heartbeat-ms is only valid for ws transport"))
    }

    func testClientStdioRejectsWSHeartbeatOptionEvenWhenDefaultProvided() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--ws-heartbeat-ms", "15000",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--ws-heartbeat-ms is only valid for ws transport"))
    }

    func testClientStdioWsOnlyOptionPrioritizesTransportScopeErrorOverRangeError() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--ws-heartbeat-ms=-1",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--ws-heartbeat-ms is only valid for ws transport"))
        XCTAssertFalse(result.stderr.contains("--ws-heartbeat-ms must be >= 0"))
    }

    func testClientStdioWSReconnectAttemptsScopeErrorOverridesRangeError() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--ws-reconnect-attempts=-1",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--ws-reconnect-attempts is only valid for ws transport"))
        XCTAssertFalse(result.stderr.contains("--ws-reconnect-attempts must be >= 0"))
    }

    func testClientStdioWSReconnectBaseDelayScopeErrorOverridesRangeError() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--ws-reconnect-base-delay-ms=-1",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--ws-reconnect-base-delay-ms is only valid for ws transport"))
        XCTAssertFalse(result.stderr.contains("--ws-reconnect-base-delay-ms must be >= 0"))
    }

    func testClientStdioMaxInFlightScopeErrorOverridesRangeError() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--max-in-flight-sends=0",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--max-in-flight-sends is only valid for ws transport"))
        XCTAssertFalse(result.stderr.contains("--max-in-flight-sends must be > 0"))
    }

    func testClientStdioRejectsWSReconnectAttemptsOption() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--ws-reconnect-attempts", "3",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--ws-reconnect-attempts is only valid for ws transport"))
    }

    func testClientStdioRejectsWSReconnectBaseDelayOption() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--ws-reconnect-base-delay-ms", "300",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--ws-reconnect-base-delay-ms is only valid for ws transport"))
    }

    func testServeStdioRejectsListenOverride() throws {
        let result = try runSKI(arguments: [
            "acp", "serve",
            "--transport", "stdio",
            "--listen", "0.0.0.0:19000"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--listen is only valid for ws transport"))
    }

    func testServeStdioRejectsListenOptionEvenWhenDefaultProvided() throws {
        let result = try runSKI(arguments: [
            "acp", "serve",
            "--transport", "stdio",
            "--listen", "127.0.0.1:8900"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--listen is only valid for ws transport"))
    }

    func testServeStdioListenScopeErrorOverridesListenFormatError() throws {
        let result = try runSKI(arguments: [
            "acp", "serve",
            "--transport", "stdio",
            "--listen", "invalid"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--listen is only valid for ws transport"))
        XCTAssertFalse(result.stderr.contains("--listen must be in host:port format"))
    }

    func testClientStdioRejectsMaxInFlightSendsOption() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "stdio",
            "--cmd", "/usr/bin/env",
            "--max-in-flight-sends", "32",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--max-in-flight-sends is only valid for ws transport"))
    }

    func testServeStdioRejectsMaxInFlightSendsOverride() throws {
        let result = try runSKI(arguments: [
            "acp", "serve",
            "--transport", "stdio",
            "--max-in-flight-sends", "32"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--max-in-flight-sends is only valid for ws transport"))
    }

    func testServeStdioRejectsMaxInFlightSendsOptionEvenWhenDefaultProvided() throws {
        let result = try runSKI(arguments: [
            "acp", "serve",
            "--transport", "stdio",
            "--max-in-flight-sends", "64"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--max-in-flight-sends is only valid for ws transport"))
    }

    func testServeRejectsInvalidMaxInFlightSends() throws {
        let result = try runSKI(arguments: [
            "acp", "serve",
            "--transport", "ws",
            "--listen", "127.0.0.1:8900",
            "--max-in-flight-sends", "0"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--max-in-flight-sends must be > 0"))
    }

    func testServeStdioMaxInFlightScopeErrorOverridesRangeError() throws {
        let result = try runSKI(arguments: [
            "acp", "serve",
            "--transport", "stdio",
            "--max-in-flight-sends=0"
        ])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--max-in-flight-sends is only valid for ws transport"))
        XCTAssertFalse(result.stderr.contains("--max-in-flight-sends must be > 0"))
    }

    func testClientConnectViaStdioServeProcessSucceeds() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let result = try runSKI(
            arguments: [
                "acp", "client", "connect",
                "--transport", "stdio",
                "--cmd", skiURL.path,
                "--args", "acp", "serve", "--transport", "stdio",
                "--prompt", "stdio process check"
            ],
            timeoutSeconds: 20
        )

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)\nstdout: \(result.stdout)")
        XCTAssertTrue(result.stdout.contains("stopReason: end_turn"), "stdout: \(result.stdout)")
    }

    func testClientConnectViaStdioResolvesCmdFromPATH() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let result = try runSKI(
            arguments: [
                "acp", "client", "connect-stdio",
                "--cmd", "env",
                "--args", skiURL.path, "--args", "acp", "--args", "serve", "--args=--transport", "--args=stdio",
                "--prompt", "stdio process path resolution check"
            ],
            timeoutSeconds: 20
        )

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)\nstdout: \(result.stdout)")
        XCTAssertTrue(result.stdout.contains("stopReason: end_turn"), "stdout: \(result.stdout)")
    }

    func testClientConnectViaStdioServeProcessJSONEmitsPromptResultType() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let result = try runSKI(
            arguments: [
                "acp", "client", "connect-stdio",
                "--cmd", skiURL.path,
                "--args", "acp", "--args", "serve", "--args=--transport", "--args=stdio",
                "--prompt", "stdio process json check",
                "--json"
            ],
            timeoutSeconds: 20
        )

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)\nstdout: \(result.stdout)")
        XCTAssertTrue(result.stderr.contains("permission requests=1"), "stderr: \(result.stderr)")
        let lines = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let last = try XCTUnwrap(lines.last, "stdout: \(result.stdout)")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: String])
        XCTAssertEqual(object["type"], "prompt_result")
        XCTAssertEqual(object["stopReason"], "end_turn")
    }

    func testClientConnectViaWSServeProcessMultiplePromptsReuseSameSession() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let port = 18911
        let server = Process()
        server.executableURL = skiURL
        server.arguments = [
            "acp", "serve",
            "--transport", "ws",
            "--listen", "127.0.0.1:\(port)",
            "--log-level", "debug"
        ]
        server.standardOutput = Pipe()
        server.standardError = Pipe()
        try server.run()
        Thread.sleep(forTimeInterval: 1.0)
        defer {
            if server.isRunning {
                server.terminate()
                server.waitUntilExit()
            }
        }

        let result = try runSKI(
            arguments: [
                "acp", "client", "connect-ws",
                "--endpoint", "ws://127.0.0.1:\(port)",
                "--prompt", "prompt-one",
                "--prompt", "prompt-two",
                "--json"
            ],
            timeoutSeconds: 20
        )

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)\nstdout: \(result.stdout)")
        XCTAssertTrue(result.stderr.contains("permission requests=1"), "stderr: \(result.stderr)")
        let lines = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let promptResults = lines.compactMap { line -> [String: String]? in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  object["type"] == "prompt_result" else {
                return nil
            }
            return object
        }

        XCTAssertEqual(promptResults.count, 2, "stdout: \(result.stdout)")
        if promptResults.count == 2 {
            XCTAssertEqual(promptResults[0]["sessionId"], promptResults[1]["sessionId"], "stdout: \(result.stdout)")
        }
    }

    func testClientConnectViaWSRequiredPermissionDenyReturnsCancelled() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let port = 18912
        let server = Process()
        server.executableURL = skiURL
        server.arguments = [
            "acp", "serve",
            "--transport", "ws",
            "--listen", "127.0.0.1:\(port)",
            "--permission-mode", "required",
            "--log-level", "debug"
        ]
        server.standardOutput = Pipe()
        server.standardError = Pipe()
        try server.run()
        Thread.sleep(forTimeInterval: 1.0)
        defer {
            if server.isRunning {
                server.terminate()
                server.waitUntilExit()
            }
        }

        let result = try runSKI(
            arguments: [
                "acp", "client", "connect-ws",
                "--endpoint", "ws://127.0.0.1:\(port)",
                "--prompt", "permission-check",
                "--permission-decision", "deny",
                "--json"
            ],
            timeoutSeconds: 20
        )

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)\nstdout: \(result.stdout)")
        let lines = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let last = try XCTUnwrap(lines.last, "stdout: \(result.stdout)")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: String])
        XCTAssertEqual(object["type"], "prompt_result")
        XCTAssertEqual(object["stopReason"], "cancelled")
    }

    func testClientConnectViaWSRequiredPermissionAllowReturnsEndTurn() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let port = 18913
        let server = Process()
        server.executableURL = skiURL
        server.arguments = [
            "acp", "serve",
            "--transport", "ws",
            "--listen", "127.0.0.1:\(port)",
            "--permission-mode", "required",
            "--log-level", "debug"
        ]
        server.standardOutput = Pipe()
        server.standardError = Pipe()
        try server.run()
        Thread.sleep(forTimeInterval: 1.0)
        defer {
            if server.isRunning {
                server.terminate()
                server.waitUntilExit()
            }
        }

        let result = try runSKI(
            arguments: [
                "acp", "client", "connect-ws",
                "--endpoint", "ws://127.0.0.1:\(port)",
                "--prompt", "permission-check",
                "--permission-decision", "allow",
                "--json"
            ],
            timeoutSeconds: 20
        )

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)\nstdout: \(result.stdout)")
        let lines = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let last = try XCTUnwrap(lines.last, "stdout: \(result.stdout)")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: String])
        XCTAssertEqual(object["type"], "prompt_result")
        XCTAssertEqual(object["stopReason"], "end_turn")
    }

    func testClientConnectViaWSDisabledPermissionReportsZeroRequests() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let port = 18914
        let server = Process()
        server.executableURL = skiURL
        server.arguments = [
            "acp", "serve",
            "--transport", "ws",
            "--listen", "127.0.0.1:\(port)",
            "--permission-mode", "disabled",
            "--log-level", "debug"
        ]
        server.standardOutput = Pipe()
        server.standardError = Pipe()
        try server.run()
        Thread.sleep(forTimeInterval: 1.0)
        defer {
            if server.isRunning {
                server.terminate()
                server.waitUntilExit()
            }
        }

        let result = try runSKI(
            arguments: [
                "acp", "client", "connect-ws",
                "--endpoint", "ws://127.0.0.1:\(port)",
                "--prompt", "permission-disabled-check",
                "--permission-decision", "deny",
                "--json"
            ],
            timeoutSeconds: 20
        )

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)\nstdout: \(result.stdout)")
        XCTAssertTrue(result.stderr.contains("permission requests=0"), "stderr: \(result.stderr)")
        let lines = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let last = try XCTUnwrap(lines.last, "stdout: \(result.stdout)")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: String])
        XCTAssertEqual(object["type"], "prompt_result")
        XCTAssertEqual(object["stopReason"], "end_turn")
    }

    func testClientConnectViaStdioServeProcessTimeoutZeroDisablesTimeout() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let result = try runSKI(
            arguments: [
                "acp", "client", "connect-stdio",
                "--cmd", skiURL.path,
                "--args", "acp", "--args", "serve", "--args=--transport", "--args=stdio",
                "--request-timeout-ms", "0",
                "--prompt", "stdio process timeout zero check"
            ],
            timeoutSeconds: 20
        )

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)\nstdout: \(result.stdout)")
        XCTAssertTrue(result.stdout.contains("stopReason: end_turn"), "stdout: \(result.stdout)")
    }

    func testClientConnectViaWSServeProcessTimeoutZeroDisablesTimeout() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let port = 18918
        let server = Process()
        server.executableURL = skiURL
        server.arguments = [
            "acp", "serve",
            "--transport", "ws",
            "--listen", "127.0.0.1:\(port)",
            "--log-level", "debug"
        ]
        server.standardOutput = Pipe()
        server.standardError = Pipe()
        try server.run()
        Thread.sleep(forTimeInterval: 1.0)
        defer {
            if server.isRunning {
                server.terminate()
                server.waitUntilExit()
            }
        }

        let result = try runSKI(
            arguments: [
                "acp", "client", "connect-ws",
                "--endpoint", "ws://127.0.0.1:\(port)",
                "--request-timeout-ms", "0",
                "--prompt", "ws process timeout zero check"
            ],
            timeoutSeconds: 20
        )

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)\nstdout: \(result.stdout)")
        XCTAssertTrue(result.stdout.contains("stopReason: end_turn"), "stdout: \(result.stdout)")
    }

    func testServeSessionTTLZeroExpiresSessionImmediatelyOverWS() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let port = 18918
        let server = Process()
        server.executableURL = skiURL
        server.arguments = [
            "acp", "serve",
            "--transport", "ws",
            "--listen", "127.0.0.1:\(port)",
            "--session-ttl-ms=0",
            "--log-level", "debug"
        ]
        server.standardOutput = Pipe()
        server.standardError = Pipe()
        try server.run()
        Thread.sleep(forTimeInterval: 1.0)
        defer {
            if server.isRunning {
                server.terminate()
                server.waitUntilExit()
            }
        }

        let result = try runSKI(
            arguments: [
                "acp", "client", "connect-ws",
                "--endpoint", "ws://127.0.0.1:\(port)",
                "--prompt", "ws session ttl zero check"
            ],
            timeoutSeconds: 20
        )

        XCTAssertEqual(result.exitCode, 4, "stderr: \(result.stderr)\nstdout: \(result.stdout)")
        XCTAssertTrue(result.stderr.contains("Session not found"), "stderr: \(result.stderr)")
    }

    func testClientConnectViaStdioWithNonexistentSessionIDFails() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let result = try runSKI(
            arguments: [
                "acp", "client", "connect-stdio",
                "--cmd", skiURL.path,
                "--args", "acp", "--args", "serve", "--args=--transport", "--args=stdio",
                "--session-id", "sess_nonexistent",
                "--prompt", "hi"
            ],
            timeoutSeconds: 20
        )

        XCTAssertEqual(result.exitCode, 4, "stderr: \(result.stderr)\nstdout: \(result.stdout)")
        XCTAssertTrue(result.stderr.contains("Error:"), "stderr: \(result.stderr)")
    }

    func testClientConnectViaStdioReusingSessionIDAcrossConnectionsFails() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let first = try runSKI(
            arguments: [
                "acp", "client", "connect-stdio",
                "--cmd", skiURL.path,
                "--args", "acp", "--args", "serve", "--args=--transport", "--args=stdio",
                "--prompt", "first",
                "--json"
            ],
            timeoutSeconds: 20
        )
        XCTAssertEqual(first.exitCode, 0, "stderr: \(first.stderr)\nstdout: \(first.stdout)")
        let firstLines = first.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("\"type\":\"prompt_result\"") }
        let firstPromptResult = try XCTUnwrap(firstLines.last, "stdout: \(first.stdout)")
        let firstObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(firstPromptResult.utf8)) as? [String: String])
        let reusedSessionID = try XCTUnwrap(firstObject["sessionId"], "stdout: \(first.stdout)")

        let second = try runSKI(
            arguments: [
                "acp", "client", "connect-stdio",
                "--cmd", skiURL.path,
                "--args", "acp", "--args", "serve", "--args=--transport", "--args=stdio",
                "--session-id", reusedSessionID,
                "--prompt", "second",
                "--json"
            ],
            timeoutSeconds: 20
        )

        XCTAssertEqual(second.exitCode, 4, "stderr: \(second.stderr)\nstdout: \(second.stdout)")
        XCTAssertTrue(
            second.stderr.contains("Resource not found") || second.stderr.contains("Error:"),
            "stderr: \(second.stderr)"
        )
    }

    func testClientConnectViaWSReusingSessionIDAcrossConnectionsSucceeds() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let port = 18915
        let server = Process()
        server.executableURL = skiURL
        server.arguments = [
            "acp", "serve",
            "--transport", "ws",
            "--listen", "127.0.0.1:\(port)",
            "--permission-mode", "permissive",
            "--log-level", "debug"
        ]
        server.standardOutput = Pipe()
        server.standardError = Pipe()
        try server.run()
        Thread.sleep(forTimeInterval: 1.0)
        defer {
            if server.isRunning {
                server.terminate()
                server.waitUntilExit()
            }
        }

        let first = try runSKI(
            arguments: [
                "acp", "client", "connect-ws",
                "--endpoint", "ws://127.0.0.1:\(port)",
                "--prompt", "first",
                "--json"
            ],
            timeoutSeconds: 20
        )
        XCTAssertEqual(first.exitCode, 0, "stderr: \(first.stderr)\nstdout: \(first.stdout)")
        let lines = first.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("\"type\":\"prompt_result\"") }
        let firstPromptResult = try XCTUnwrap(lines.last, "stdout: \(first.stdout)")
        let firstObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(firstPromptResult.utf8)) as? [String: String])
        let reusedSessionID = try XCTUnwrap(firstObject["sessionId"], "stdout: \(first.stdout)")

        let second = try runSKI(
            arguments: [
                "acp", "client", "connect-ws",
                "--endpoint", "ws://127.0.0.1:\(port)",
                "--session-id", reusedSessionID,
                "--prompt", "second",
                "--json"
            ],
            timeoutSeconds: 20
        )

        XCTAssertEqual(second.exitCode, 0, "stderr: \(second.stderr)\nstdout: \(second.stdout)")
        let secondLines = second.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("\"type\":\"prompt_result\"") }
        let secondPromptResult = try XCTUnwrap(secondLines.last, "stdout: \(second.stdout)")
        let secondObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(secondPromptResult.utf8)) as? [String: String])
        XCTAssertEqual(secondObject["sessionId"], reusedSessionID, "stdout: \(second.stdout)")
        XCTAssertEqual(secondObject["stopReason"], "end_turn")
    }

    func testClientConnectViaWSWithNonexistentSessionIDFails() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let port = 18916
        let server = Process()
        server.executableURL = skiURL
        server.arguments = [
            "acp", "serve",
            "--transport", "ws",
            "--listen", "127.0.0.1:\(port)",
            "--permission-mode", "permissive",
            "--log-level", "debug"
        ]
        server.standardOutput = Pipe()
        server.standardError = Pipe()
        try server.run()
        Thread.sleep(forTimeInterval: 1.0)
        defer {
            if server.isRunning {
                server.terminate()
                server.waitUntilExit()
            }
        }

        let result = try runSKI(
            arguments: [
                "acp", "client", "connect-ws",
                "--endpoint", "ws://127.0.0.1:\(port)",
                "--session-id", "sess_nonexistent",
                "--prompt", "hello",
                "--json"
            ],
            timeoutSeconds: 20
        )

        XCTAssertEqual(result.exitCode, 4, "stderr: \(result.stderr)\nstdout: \(result.stdout)")
        XCTAssertTrue(
            result.stderr.contains("Could not route request to client owner by sessionId") || result.stderr.contains("Error:"),
            "stderr: \(result.stderr)"
        )
    }

    func testClientStopViaWSReturnsSessionStopJSON() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let port = 18917
        let server = Process()
        server.executableURL = skiURL
        server.arguments = [
            "acp", "serve",
            "--transport", "ws",
            "--listen", "127.0.0.1:\(port)",
            "--permission-mode", "permissive",
            "--log-level", "debug"
        ]
        server.standardOutput = Pipe()
        server.standardError = Pipe()
        try server.run()
        Thread.sleep(forTimeInterval: 1.0)
        defer {
            if server.isRunning {
                server.terminate()
                server.waitUntilExit()
            }
        }

        let createResult = try runSKI(
            arguments: [
                "acp", "client", "connect-ws",
                "--endpoint", "ws://127.0.0.1:\(port)",
                "--prompt", "hello",
                "--json"
            ],
            timeoutSeconds: 20
        )
        XCTAssertEqual(createResult.exitCode, 0, "stderr: \(createResult.stderr)\nstdout: \(createResult.stdout)")
        let promptLine = try XCTUnwrap(
            createResult.stdout
                .split(separator: "\n")
                .map(String.init)
                .last(where: { $0.contains("\"type\":\"prompt_result\"") }),
            "stdout: \(createResult.stdout)"
        )
        let promptObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(promptLine.utf8)) as? [String: String])
        let sessionID = try XCTUnwrap(promptObject["sessionId"])

        let stopResult = try runSKI(
            arguments: [
                "acp", "client", "stop",
                "--transport", "ws",
                "--endpoint", "ws://127.0.0.1:\(port)",
                "--session-id", sessionID,
                "--json"
            ],
            timeoutSeconds: 20
        )
        XCTAssertEqual(stopResult.exitCode, 0, "stderr: \(stopResult.stderr)\nstdout: \(stopResult.stdout)")
        let stopLine = try XCTUnwrap(
            stopResult.stdout
                .split(separator: "\n")
                .map(String.init)
                .last(where: { $0.contains("\"type\":\"session_stop\"") }),
            "stdout: \(stopResult.stdout)"
        )
        let stopObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(stopLine.utf8)) as? [String: String])
        XCTAssertEqual(stopObject["sessionId"], sessionID)
        XCTAssertEqual(stopObject["type"], "session_stop")
    }

    func testClientStopWSAliasReturnsSessionStopJSON() throws {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let port = 18919
        let server = Process()
        server.executableURL = skiURL
        server.arguments = [
            "acp", "serve",
            "--transport", "ws",
            "--listen", "127.0.0.1:\(port)",
            "--permission-mode", "permissive",
            "--log-level", "debug"
        ]
        server.standardOutput = Pipe()
        server.standardError = Pipe()
        try server.run()
        Thread.sleep(forTimeInterval: 1.0)
        defer {
            if server.isRunning {
                server.terminate()
                server.waitUntilExit()
            }
        }

        let createResult = try runSKI(
            arguments: [
                "acp", "client", "connect-ws",
                "--endpoint", "ws://127.0.0.1:\(port)",
                "--prompt", "hello",
                "--json"
            ],
            timeoutSeconds: 20
        )
        XCTAssertEqual(createResult.exitCode, 0, "stderr: \(createResult.stderr)\nstdout: \(createResult.stdout)")
        let promptLine = try XCTUnwrap(
            createResult.stdout
                .split(separator: "\n")
                .map(String.init)
                .last(where: { $0.contains("\"type\":\"prompt_result\"") }),
            "stdout: \(createResult.stdout)"
        )
        let promptObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(promptLine.utf8)) as? [String: String])
        let sessionID = try XCTUnwrap(promptObject["sessionId"])

        let stopResult = try runSKI(
            arguments: [
                "acp", "client", "stop-ws",
                "--endpoint", "ws://127.0.0.1:\(port)",
                "--session-id", sessionID,
                "--json"
            ],
            timeoutSeconds: 20
        )
        XCTAssertEqual(stopResult.exitCode, 0, "stderr: \(stopResult.stderr)\nstdout: \(stopResult.stdout)")
        let stopLine = try XCTUnwrap(
            stopResult.stdout
                .split(separator: "\n")
                .map(String.init)
                .last(where: { $0.contains("\"type\":\"session_stop\"") }),
            "stdout: \(stopResult.stdout)"
        )
        let stopObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(stopLine.utf8)) as? [String: String])
        XCTAssertEqual(stopObject["sessionId"], sessionID)
        XCTAssertEqual(stopObject["type"], "session_stop")
    }
}

private extension SKICLIProcessTests {
    struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    func runSKI(arguments: [String], timeoutSeconds: TimeInterval = 10) throws -> ProcessResult {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let process = Process()
        process.executableURL = skiURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            XCTFail("ski process timed out after \(timeoutSeconds)s for args: \(arguments)")
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }

    func findSKIBinary() -> URL? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            ".build/arm64-apple-macosx/debug/ski",
            ".build/x86_64-apple-macosx/debug/ski",
            ".build/debug/ski"
        ]
        for relative in candidates {
            let candidate = root.appendingPathComponent(relative)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
