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

    mutating func run() async throws {
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
                    sessionCapabilities: .init(list: .init(), resume: .init(), fork: .init(), delete: .init()),
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
        subcommands: [ACPClientConnectCommand.self]
    )
}

struct ACPClientConnectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connect",
        abstract: "Connect and run one prompt"
    )

    @Option(name: .long)
    var transport: CLITransport = .stdio

    @Option(name: .long)
    var cmd: String?

    @Option(name: .long, parsing: .upToNextOption)
    var args: [String] = []

    @Option(name: .long)
    var endpoint: String?

    @Option(name: .long)
    var cwd: String = FileManager.default.currentDirectoryPath

    @Option(name: .long)
    var prompt: String

    @Flag(name: .long)
    var json: Bool = false

    @Option(name: .long, help: "Request timeout in milliseconds")
    var requestTimeoutMS: Int?

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

    @Option(name: .long, help: "Permission response message")
    var permissionMessage: String?

    mutating func run() async throws {
        let jsonOutput = json
        let requestTimeoutNanos = ACPCLITransportFactory.millisecondsToNanosecondsNonNegative(requestTimeoutMS)
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
            _ = permissionMessage

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

            let session = try await client.newSession(.init(cwd: cwd))
            let result = try await client.prompt(.init(sessionId: session.sessionId, prompt: [.text(prompt)]))

            if jsonOutput {
                let json = try ACPCLIOutputFormatter.promptResultJSON(
                    sessionId: session.sessionId,
                    stopReason: result.stopReason.rawValue
                )
                print(json)
            } else {
                print("stopReason: \(result.stopReason.rawValue)")
            }
        } catch {
            let code = SKICLIExitCodeMapper.exitCode(for: error)
            fputs("Error: \(error.localizedDescription)\n", stderr)
            throw ExitCode(Int32(code.rawValue))
        }
    }
}
