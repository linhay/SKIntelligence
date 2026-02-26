import ArgumentParser
import Foundation
import SKIACP
import SKIACPAgent
import SKIACPClient
import SKIACPTransport
import SKICLIShared
import SKIJSONRPC
import SKIntelligence

typealias CLIError = SKICLIValidationError

enum CLITransport: String, ExpressibleByArgument {
    case stdio
    case ws
}

enum CLILogLevel: String, ExpressibleByArgument {
    case error
    case warn
    case info
    case debug
}

enum CLIServePermissionMode: String, ExpressibleByArgument {
    case disabled
    case permissive
    case required

    var shared: SKICLIServePermissionMode {
        switch self {
        case .disabled: return .disabled
        case .permissive: return .permissive
        case .required: return .required
        }
    }
}

enum CLIClientPermissionDecision: String, ExpressibleByArgument {
    case allow
    case deny

    var shared: SKICLIClientPermissionDecision {
        switch self {
        case .allow: return .allow
        case .deny: return .deny
        }
    }
}

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct SKI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ski",
        abstract: "SKIntelligence CLI",
        subcommands: [ACPCommand.self]
    )
}

struct ACPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "acp",
        abstract: "ACP commands",
        subcommands: [ACPServeCommand.self, ACPClientCommand.self]
    )
}

struct ACPServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run as ACP agent server"
    )

    @Option(name: .long)
    var transport: CLITransport = .stdio

    @Option(name: .long)
    var listen: String = "127.0.0.1:8900"

    @Option(name: .long, help: "Prompt timeout in milliseconds")
    var promptTimeoutMS: Int?

    @Option(name: [.customLong("session-ttl-ms")], help: "Session TTL in milliseconds")
    var sessionTTLMS: Int?

    @Option(name: .long)
    var logLevel: CLILogLevel = .info

    @Option(name: .long, help: "Maximum in-flight websocket sends")
    var maxInFlightSends: Int = 64

    @Option(name: .long, help: "Permission mode: disabled | permissive | required")
    var permissionMode: CLIServePermissionMode = .permissive

    @Option(name: .long, help: "Permission request timeout in milliseconds")
    var permissionTimeoutMS: Int = 10_000

    private func hasExplicitOption(_ option: String) -> Bool {
        CommandLine.arguments.contains { arg in
            arg == option || arg.hasPrefix("\(option)=")
        }
    }

    mutating func run() async throws {
        if let promptTimeoutMS, promptTimeoutMS < 0 {
            fputs("Error: --prompt-timeout-ms must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if let sessionTTLMS, sessionTTLMS < 0 {
            fputs("Error: --session-ttl-ms must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if permissionTimeoutMS < 0 {
            fputs("Error: --permission-timeout-ms must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if maxInFlightSends <= 0 {
            fputs("Error: --max-in-flight-sends must be > 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if transport == .stdio, hasExplicitOption("--listen") {
            fputs("Error: --listen is only valid for ws transport\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if transport == .stdio, hasExplicitOption("--max-in-flight-sends") {
            fputs("Error: --max-in-flight-sends is only valid for ws transport\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if permissionMode == .disabled, hasExplicitOption("--permission-timeout-ms") {
            fputs("Error: --permission-timeout-ms is only valid when --permission-mode is permissive or required\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }

        let timeoutNanos = promptTimeoutMS.map { UInt64(max($0, 0)) * 1_000_000 }
        let ttlNanos = sessionTTLMS.map { UInt64(max($0, 0)) * 1_000_000 }
        let transportKind: SKICLITransportKind = transport == .ws ? .ws : .stdio
        let transportImpl: any ACPTransport
        do {
            transportImpl = try ACPCLITransportFactory.makeServerTransport(
                kind: transportKind,
                listen: listen,
                maxInFlightSends: maxInFlightSends
            )
        } catch let error as SKICLIValidationError {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }

        do {
            try await transportImpl.connect()
            if logLevel == .debug || logLevel == .info {
                fputs("[SKI] ACP server started transport=\(transport.rawValue)\n", stderr)
            }
            let servePermissionMode = permissionMode.shared
            let permissionBridge: ACPPermissionRequestBridge? = servePermissionMode.enabled
                ? ACPPermissionRequestBridge(
                    timeoutNanoseconds: ACPCLITransportFactory.millisecondsToNanosecondsNonNegative(permissionTimeoutMS)
                )
                : nil
            let policyMode: ACPPermissionPolicyMode = {
                switch servePermissionMode.policyMode {
                case .ask: return .ask
                case .allow: return .allow
                case .deny: return .deny
                }
            }()
            let permissionPolicy = ACPBridgeBackedPermissionPolicy(
                mode: policyMode,
                allowOnBridgeError: servePermissionMode.allowOnBridgeError,
                requester: { params in
                    guard let permissionBridge else {
                        throw ACPTransportError.notConnected
                    }
                    return try await permissionBridge.requestPermission(params) { request in
                        try await transportImpl.send(.request(request))
                    }
                }
            )

            let service = ACPAgentService(
                sessionFactory: {
                    SKILanguageModelSession(client: EchoLanguageModelClient())
                },
                agentInfo: ACPImplementationInfo(name: "ski", title: "SKI ACP Agent", version: "0.1.0"),
                capabilities: ACPAgentCapabilities(
                    sessionCapabilities: .init(list: .init(), resume: .init(), fork: .init(), delete: .init(), export: .init()),
                    loadSession: true
                ),
                options: .init(promptTimeoutNanoseconds: timeoutNanos, sessionTTLNanos: ttlNanos),
                permissionPolicy: permissionPolicy,
                notificationSink: { notification in
                    try? await transportImpl.send(.notification(notification))
                }
            )

            while let message = try await transportImpl.receive() {
                switch message {
                case .request(let request):
                    if transport == .stdio {
                        let response = await service.handle(request)
                        try? await transportImpl.send(.response(response))
                    } else {
                        Task {
                            let response = await service.handle(request)
                            try? await transportImpl.send(.response(response))
                        }
                    }
                case .notification(let notification):
                    await service.handleCancel(notification)
                case .response(let response):
                    if let permissionBridge {
                        _ = await permissionBridge.handleIncomingResponse(response)
                    }
                }
            }
            if let permissionBridge {
                await permissionBridge.failAll(ACPTransportError.eof)
            }
        } catch {
            let code = SKICLIExitCodeMapper.exitCode(for: error)
            fputs("Error: \(error.localizedDescription)\n", stderr)
            throw ExitCode(Int32(code.rawValue))
        }
    }
}

struct ACPClientCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "client",
        abstract: "Run as ACP client",
        subcommands: [ACPClientConnectCommand.self, ACPClientConnectStdioCommand.self, ACPClientConnectWSCommand.self]
    )
}

struct ACPClientConnectStdioCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connect-stdio",
        abstract: "Connect via stdio and run one prompt",
        discussion: """
            Example:
              ski acp client connect-stdio --cmd ski --args acp --args serve --args=--transport --args=stdio --prompt "hello"
            Note:
              For child arguments starting with '-', use --args=--flag to avoid parent option parsing.
            """
    )

    @Option(name: .long, help: "Child executable path or command name in PATH")
    var cmd: String?

    @Option(name: .long, parsing: .upToNextOption)
    var args: [String] = []

    @Option(name: .long, help: "Working directory sent to session/new.")
    var cwd: String = FileManager.default.currentDirectoryPath

    @Option(name: .long, help: "Prompt text. Repeat --prompt for multi-turn prompts in one connection.")
    var prompt: [String] = []

    @Option(name: .long, help: "Reuse an existing ACP session ID instead of creating a new one")
    var sessionID: String?

    @Flag(name: .long)
    var json: Bool = false

    @Option(name: .long, help: "Request timeout in milliseconds (0 disables)")
    var requestTimeoutMS: Int = 60_000

    @Option(name: .long)
    var logLevel: CLILogLevel = .info

    @Option(name: .long, help: "Permission decision: allow | deny")
    var permissionDecision: CLIClientPermissionDecision = .allow

    @Option(name: .long, help: "Informational only. Printed locally; not sent to ACP server")
    var permissionMessage: String?

    mutating func run() async throws {
        if prompt.isEmpty {
            fputs("Error: --prompt must be provided at least once\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if prompt.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            fputs("Error: --prompt must not be empty\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if let sessionID, sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fputs("Error: --session-id must not be empty when provided\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if requestTimeoutMS < 0 {
            fputs("Error: --request-timeout-ms must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        var isDirectory = ObjCBool(false)
        if !FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory) || !isDirectory.boolValue {
            fputs("Error: --cwd must be an existing directory\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }

        try await runACPClientConnect(
            transport: .stdio,
            cmd: cmd,
            args: args,
            endpoint: nil,
            cwd: cwd,
            prompts: prompt,
            sessionID: sessionID,
            jsonOutput: json,
            requestTimeoutMS: requestTimeoutMS,
            logLevel: logLevel,
            wsHeartbeatMS: 15_000,
            wsReconnectAttempts: 2,
            wsReconnectBaseDelayMS: 200,
            maxInFlightSends: 64,
            permissionDecision: permissionDecision,
            permissionMessage: permissionMessage
        )
    }
}

struct ACPClientConnectWSCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connect-ws",
        abstract: "Connect via websocket and run one prompt"
    )

    @Option(name: .long)
    var endpoint: String?

    @Option(name: .long, help: "Working directory sent to session/new. Use a path valid on the server.")
    var cwd: String = FileManager.default.currentDirectoryPath

    @Option(name: .long, help: "Prompt text. Repeat --prompt for multi-turn prompts in one connection.")
    var prompt: [String] = []

    @Option(name: .long, help: "Reuse an existing ACP session ID instead of creating a new one")
    var sessionID: String?

    @Flag(name: .long)
    var json: Bool = false

    @Option(name: .long, help: "Request timeout in milliseconds (0 disables)")
    var requestTimeoutMS: Int = 60_000

    @Option(name: .long)
    var logLevel: CLILogLevel = .info

    @Option(name: .long, help: "WebSocket heartbeat interval in milliseconds (0 disables)")
    var wsHeartbeatMS: Int = 15_000

    @Option(name: .long, help: "WebSocket reconnect max attempts")
    var wsReconnectAttempts: Int = 2

    @Option(name: .long, help: "WebSocket reconnect base delay in milliseconds")
    var wsReconnectBaseDelayMS: Int = 200

    @Option(name: .long, help: "Maximum in-flight websocket sends")
    var maxInFlightSends: Int = 64

    @Option(name: .long, help: "Permission decision: allow | deny")
    var permissionDecision: CLIClientPermissionDecision = .allow

    @Option(name: .long, help: "Informational only. Printed locally; not sent to ACP server")
    var permissionMessage: String?

    mutating func run() async throws {
        if prompt.isEmpty {
            fputs("Error: --prompt must be provided at least once\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if prompt.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            fputs("Error: --prompt must not be empty\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if let sessionID, sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fputs("Error: --session-id must not be empty when provided\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if requestTimeoutMS < 0 {
            fputs("Error: --request-timeout-ms must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if wsHeartbeatMS < 0 {
            fputs("Error: --ws-heartbeat-ms must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if wsReconnectAttempts < 0 {
            fputs("Error: --ws-reconnect-attempts must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if wsReconnectBaseDelayMS < 0 {
            fputs("Error: --ws-reconnect-base-delay-ms must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if maxInFlightSends <= 0 {
            fputs("Error: --max-in-flight-sends must be > 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }

        try await runACPClientConnect(
            transport: .ws,
            cmd: nil,
            args: [],
            endpoint: endpoint,
            cwd: cwd,
            prompts: prompt,
            sessionID: sessionID,
            jsonOutput: json,
            requestTimeoutMS: requestTimeoutMS,
            logLevel: logLevel,
            wsHeartbeatMS: wsHeartbeatMS,
            wsReconnectAttempts: wsReconnectAttempts,
            wsReconnectBaseDelayMS: wsReconnectBaseDelayMS,
            maxInFlightSends: maxInFlightSends,
            permissionDecision: permissionDecision,
            permissionMessage: permissionMessage
        )
    }
}

struct ACPClientConnectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connect",
        abstract: "Connect and run one prompt",
        discussion: """
            Examples:
              ski acp client connect --transport stdio --cmd ./ski --args acp --args serve --args=--transport --args=stdio --prompt "hello"
              ski acp client connect --transport ws --endpoint ws://127.0.0.1:8900 --prompt "hello" --json
            Note:
              For child arguments starting with '-', use --args=--flag to avoid parent option parsing.
            """
    )

    @Option(name: .long)
    var transport: CLITransport = .stdio

    @Option(name: .long, help: "Child executable path or command name in PATH")
    var cmd: String?

    @Option(name: .long, parsing: .upToNextOption)
    var args: [String] = []

    @Option(name: .long)
    var endpoint: String?

    @Option(name: .long, help: "Working directory sent to session/new. For ws transport, use a path valid on the server.")
    var cwd: String = FileManager.default.currentDirectoryPath

    @Option(name: .long, help: "Prompt text. Repeat --prompt for multi-turn prompts in one connection.")
    var prompt: [String] = []

    @Option(name: .long, help: "Reuse an existing ACP session ID instead of creating a new one")
    var sessionID: String?

    @Flag(name: .long)
    var json: Bool = false

    @Option(name: .long, help: "Request timeout in milliseconds (0 disables)")
    var requestTimeoutMS: Int = 60_000

    @Option(name: .long)
    var logLevel: CLILogLevel = .info

    @Option(name: .long, help: "WebSocket heartbeat interval in milliseconds (0 disables)")
    var wsHeartbeatMS: Int = 15_000

    @Option(name: .long, help: "WebSocket reconnect max attempts")
    var wsReconnectAttempts: Int = 2

    @Option(name: .long, help: "WebSocket reconnect base delay in milliseconds")
    var wsReconnectBaseDelayMS: Int = 200

    @Option(name: .long, help: "Maximum in-flight websocket sends")
    var maxInFlightSends: Int = 64

    @Option(name: .long, help: "Permission decision: allow | deny")
    var permissionDecision: CLIClientPermissionDecision = .allow

    @Option(name: .long, help: "Informational only. Printed locally; not sent to ACP server")
    var permissionMessage: String?

    private func hasExplicitOption(_ option: String) -> Bool {
        CommandLine.arguments.contains { arg in
            arg == option || arg.hasPrefix("\(option)=")
        }
    }

    mutating func run() async throws {
        if prompt.isEmpty {
            fputs("Error: --prompt must be provided at least once\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if prompt.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            fputs("Error: --prompt must not be empty\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if let sessionID, sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fputs("Error: --session-id must not be empty when provided\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if transport == .stdio, hasExplicitOption("--endpoint") {
            fputs("Error: --endpoint is only valid for ws transport\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if transport == .stdio, hasExplicitOption("--ws-heartbeat-ms") {
            fputs("Error: --ws-heartbeat-ms is only valid for ws transport\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if transport == .stdio, hasExplicitOption("--ws-reconnect-attempts") {
            fputs("Error: --ws-reconnect-attempts is only valid for ws transport\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if transport == .stdio, hasExplicitOption("--ws-reconnect-base-delay-ms") {
            fputs("Error: --ws-reconnect-base-delay-ms is only valid for ws transport\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if transport == .stdio, hasExplicitOption("--max-in-flight-sends") {
            fputs("Error: --max-in-flight-sends is only valid for ws transport\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if requestTimeoutMS < 0 {
            fputs("Error: --request-timeout-ms must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if wsHeartbeatMS < 0 {
            fputs("Error: --ws-heartbeat-ms must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if wsReconnectAttempts < 0 {
            fputs("Error: --ws-reconnect-attempts must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if wsReconnectBaseDelayMS < 0 {
            fputs("Error: --ws-reconnect-base-delay-ms must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if maxInFlightSends <= 0 {
            fputs("Error: --max-in-flight-sends must be > 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if transport == .stdio {
            var isDirectory = ObjCBool(false)
            if !FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory) || !isDirectory.boolValue {
                fputs("Error: --cwd must be an existing directory\n", stderr)
                throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
            }
        }
        if transport == .ws, cmd != nil {
            if hasExplicitOption("--args") {
                fputs("Error: --cmd is only valid for stdio transport (if child args start with '-', pass as --args=--flag)\n", stderr)
                throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
            }
            fputs("Error: --cmd is only valid for stdio transport\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if transport == .ws, !args.isEmpty {
            fputs("Error: --args is only valid for stdio transport\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }

        try await runACPClientConnect(
            transport: transport,
            cmd: cmd,
            args: args,
            endpoint: endpoint,
            cwd: cwd,
            prompts: prompt,
            sessionID: sessionID,
            jsonOutput: json,
            requestTimeoutMS: requestTimeoutMS,
            logLevel: logLevel,
            wsHeartbeatMS: wsHeartbeatMS,
            wsReconnectAttempts: wsReconnectAttempts,
            wsReconnectBaseDelayMS: wsReconnectBaseDelayMS,
            maxInFlightSends: maxInFlightSends,
            permissionDecision: permissionDecision,
            permissionMessage: permissionMessage
        )
    }
}

private func runACPClientConnect(
    transport: CLITransport,
    cmd: String?,
    args: [String],
    endpoint: String?,
    cwd: String,
    prompts: [String],
    sessionID: String?,
    jsonOutput: Bool,
    requestTimeoutMS: Int,
    logLevel: CLILogLevel,
    wsHeartbeatMS: Int,
    wsReconnectAttempts: Int,
    wsReconnectBaseDelayMS: Int,
    maxInFlightSends: Int,
    permissionDecision: CLIClientPermissionDecision,
    permissionMessage: String?
) async throws {
    let requestTimeoutNanos: UInt64? = requestTimeoutMS == 0
        ? nil
        : ACPCLITransportFactory.millisecondsToNanosecondsNonNegative(requestTimeoutMS)
    let transportKind: SKICLITransportKind = transport == .ws ? .ws : .stdio
    let transportImpl: any ACPTransport
    do {
        transportImpl = try ACPCLITransportFactory.makeClientTransport(
            kind: transportKind,
            cmd: cmd,
            args: args,
            endpoint: endpoint,
            wsHeartbeatMS: wsHeartbeatMS,
            wsReconnectAttempts: wsReconnectAttempts,
            wsReconnectBaseDelayMS: wsReconnectBaseDelayMS,
            maxInFlightSends: maxInFlightSends
        )
    } catch let error as SKICLIValidationError {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
    }

    do {
        if logLevel == .debug || logLevel == .info {
            fputs("[SKI] ACP client connecting transport=\(transport.rawValue)\n", stderr)
        }
        let client = ACPClientService(transport: transportImpl, requestTimeoutNanoseconds: requestTimeoutNanos)
        let terminalRuntime = ACPProcessTerminalRuntime()
        let filesystemRuntime = ACPLocalFilesystemRuntime(policy: .unrestricted)
        let permissionAllow = permissionDecision.shared.allowValue
        if permissionMessage != nil {
            fputs("Warning: --permission-message is informational only and is not sent to the ACP server\n", stderr)
        }

        await client.setNotificationHandler { notification in
            guard notification.method == ACPMethods.sessionUpdate,
                  let params = try? ACPCodec.decodeParams(notification.params, as: ACPSessionUpdateParams.self) else {
                return
            }

            if jsonOutput {
                if let text = try? ACPCLIOutputFormatter.sessionUpdateJSON(
                    sessionId: params.sessionId,
                    update: params.update.sessionUpdate.rawValue,
                    text: params.update.content?.text ?? ""
                ) {
                    print(text)
                }
            } else if let text = params.update.content?.text {
                print(text)
            }
        }
        await client.setPermissionRequestHandler { _ in
            ACPSessionPermissionRequestResult(outcome: permissionAllow ? .selected(.init(optionId: "allow_once")) : .cancelled)
        }
        await client.installRuntimes(filesystem: filesystemRuntime, terminal: terminalRuntime)

        try await client.connect()
        defer {
            Task { await client.close() }
        }

        _ = try await client.initialize(.init(
            protocolVersion: 1,
            clientCapabilities: .init(fs: .init(readTextFile: true, writeTextFile: true), terminal: true),
            clientInfo: .init(name: "ski", title: "SKI ACP Client", version: "0.1.0")
        ))

        let effectiveSessionID: String
        if let sessionID, !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            effectiveSessionID = sessionID
        } else {
            let session = try await client.newSession(.init(cwd: cwd))
            effectiveSessionID = session.sessionId
        }
        for prompt in prompts {
            let result = try await client.prompt(.init(sessionId: effectiveSessionID, prompt: [.text(prompt)]))
            if jsonOutput {
                let json = try ACPCLIOutputFormatter.promptResultJSON(
                    sessionId: effectiveSessionID,
                    stopReason: result.stopReason.rawValue
                )
                print(json)
            } else {
                print("stopReason: \(result.stopReason.rawValue)")
            }
        }
    } catch {
        let code = SKICLIExitCodeMapper.exitCode(for: error)
        fputs("Error: \(error.localizedDescription)\n", stderr)
        throw ExitCode(Int32(code.rawValue))
    }
}
