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
            let terminals = CLITerminalRegistry()
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
            await client.setReadTextFileHandler { params in
                let url = URL(fileURLWithPath: params.path)
                let content = try String(contentsOf: url, encoding: .utf8)
                guard let line = params.line, let limit = params.limit else {
                    return .init(content: content)
                }

                let lines = content.components(separatedBy: .newlines)
                let start = max(0, line - 1)
                let end = min(lines.count, start + max(0, limit))
                if start >= end {
                    return .init(content: "")
                }
                return .init(content: lines[start..<end].joined(separator: "\n"))
            }
            await client.setWriteTextFileHandler { params in
                try params.content.write(to: URL(fileURLWithPath: params.path), atomically: true, encoding: .utf8)
                return .init()
            }
            await client.setTerminalCreateHandler { params in
                try await terminals.create(params)
            }
            await client.setTerminalOutputHandler { params in
                try await terminals.output(params)
            }
            await client.setTerminalWaitForExitHandler { params in
                try await terminals.waitForExit(params)
            }
            await client.setTerminalKillHandler { params in
                try await terminals.kill(params)
            }
            await client.setTerminalReleaseHandler { params in
                try await terminals.release(params)
            }

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

private actor CLITerminalRegistry {
    private struct Entry {
        let process: Process
        let stdout: Pipe
        var output: String
        var truncated: Bool
        let limit: Int?
        var didExit: Bool
        var terminationStatus: Int32
        var waiters: [CheckedContinuation<ACPTerminalWaitForExitResult, Error>]
    }

    private var entries: [String: Entry] = [:]

    func create(_ params: ACPTerminalCreateParams) async throws -> ACPTerminalCreateResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: params.command)
        process.arguments = params.args
        if let cwd = params.cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        if !params.env.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for item in params.env {
                env[item.name] = item.value
            }
            process.environment = env
        }

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = stdout

        let terminalID = "term_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        entries[terminalID] = Entry(
            process: process,
            stdout: stdout,
            output: "",
            truncated: false,
            limit: params.outputByteLimit,
            didExit: false,
            terminationStatus: 0,
            waiters: []
        )

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.appendOutput(data, terminalID: terminalID) }
        }

        process.terminationHandler = { [weak self] proc in
            Task { await self?.markExit(terminalID: terminalID, status: proc.terminationStatus) }
        }
        try process.run()
        return .init(terminalId: terminalID)
    }

    func output(_ params: ACPTerminalRefParams) throws -> ACPTerminalOutputResult {
        guard let entry = entries[params.terminalId] else {
            throw NSError(domain: "CLITerminal", code: 404, userInfo: [NSLocalizedDescriptionKey: "Unknown terminalId: \(params.terminalId)"])
        }
        let exitStatus = entry.didExit ? ACPTerminalExitStatus(exitCode: Int(entry.terminationStatus), signal: nil) : nil
        return .init(output: entry.output, truncated: entry.truncated, exitStatus: exitStatus)
    }

    func waitForExit(_ params: ACPTerminalRefParams) async throws -> ACPTerminalWaitForExitResult {
        guard var entry = entries[params.terminalId] else {
            throw NSError(domain: "CLITerminal", code: 404, userInfo: [NSLocalizedDescriptionKey: "Unknown terminalId: \(params.terminalId)"])
        }
        if entry.didExit {
            return .init(exitCode: Int(entry.terminationStatus), signal: nil)
        }
        return try await withCheckedThrowingContinuation { continuation in
            entry.waiters.append(continuation)
            entries[params.terminalId] = entry
        }
    }

    func kill(_ params: ACPTerminalRefParams) throws -> ACPTerminalKillResult {
        guard let entry = entries[params.terminalId] else {
            throw NSError(domain: "CLITerminal", code: 404, userInfo: [NSLocalizedDescriptionKey: "Unknown terminalId: \(params.terminalId)"])
        }
        if entry.process.isRunning {
            entry.process.terminate()
        }
        return .init()
    }

    func release(_ params: ACPTerminalRefParams) throws -> ACPTerminalReleaseResult {
        guard let entry = entries.removeValue(forKey: params.terminalId) else {
            throw NSError(domain: "CLITerminal", code: 404, userInfo: [NSLocalizedDescriptionKey: "Unknown terminalId: \(params.terminalId)"])
        }
        entry.stdout.fileHandleForReading.readabilityHandler = nil
        if !entry.didExit {
            for waiter in entry.waiters {
                waiter.resume(throwing: ACPTransportError.eof)
            }
        }
        return .init()
    }

    private func appendOutput(_ data: Data, terminalID: String) {
        guard var entry = entries[terminalID] else { return }
        let chunk = String(decoding: data, as: UTF8.self)
        entry.output += chunk
        if let limit = entry.limit, limit >= 0 {
            while entry.output.utf8.count > limit {
                entry.truncated = true
                entry.output.removeFirst()
            }
        }
        entries[terminalID] = entry
    }

    private func markExit(terminalID: String, status: Int32) {
        guard var entry = entries[terminalID] else { return }
        entry.didExit = true
        entry.terminationStatus = status
        let waiters = entry.waiters
        entry.waiters.removeAll()
        entries[terminalID] = entry
        for waiter in waiters {
            waiter.resume(returning: .init(exitCode: Int(status), signal: nil))
        }
    }
}
