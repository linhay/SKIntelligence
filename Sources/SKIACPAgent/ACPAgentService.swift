import Foundation
import SKIACP
import SKIJSONRPC
import SKIntelligence

public enum ACPAgentServiceError: Error, LocalizedError {
    case methodNotFound(String)
    case invalidParams(String)
    case sessionNotFound(String)
    case promptTimedOut
    case requestCancelled

    public var errorDescription: String? {
        switch self {
        case .methodNotFound(let method):
            return "Method not found: \(method)"
        case .invalidParams(let message):
            return "Invalid params: \(message)"
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .promptTimedOut:
            return "Prompt timed out"
        case .requestCancelled:
            return "Request cancelled"
        }
    }
}

public actor ACPAgentService {
    public struct Options: Sendable {
        public var promptTimeoutNanoseconds: UInt64?
        public var sessionTTLNanos: UInt64?
        public var sessionListPageSize: Int
        public var autoSessionInfoUpdateOnFirstPrompt: Bool

        public init(
            promptTimeoutNanoseconds: UInt64? = nil,
            sessionTTLNanos: UInt64? = nil,
            sessionListPageSize: Int = 50,
            autoSessionInfoUpdateOnFirstPrompt: Bool = false
        ) {
            self.promptTimeoutNanoseconds = promptTimeoutNanoseconds
            self.sessionTTLNanos = sessionTTLNanos
            self.sessionListPageSize = max(1, sessionListPageSize)
            self.autoSessionInfoUpdateOnFirstPrompt = autoSessionInfoUpdateOnFirstPrompt
        }
    }

    public typealias SessionFactory = @Sendable () throws -> any ACPAgentSession
    public typealias NotificationSink = @Sendable (JSONRPCNotification) async -> Void
    public typealias PermissionRequester = @Sendable (ACPSessionPermissionRequestParams) async throws -> ACPSessionPermissionRequestResult
    public typealias AuthenticationHandler = @Sendable (ACPAuthenticateParams) async throws -> Void

    private let sessionFactory: SessionFactory
    private let agentInfo: ACPImplementationInfo
    private let capabilities: ACPAgentCapabilities
    private let authMethods: [ACPAuthMethod]
    private let authenticationHandler: AuthenticationHandler?
    private let options: Options
    private let permissionRequester: PermissionRequester?
    private let permissionPolicy: (any ACPPermissionPolicy)?
    private let notificationSink: NotificationSink

    private struct SessionEntry {
        let session: any ACPAgentSession
        var cwd: String
        var title: String?
        var updatedAt: String
        var currentModeId: String?
        var availableModes: [ACPSessionMode]
        var currentModelId: String?
        var availableModels: [ACPModelInfo]
        var configOptions: [ACPSessionConfigOption]
        var lastTouchedNanos: UInt64
    }
    private var sessions: [String: SessionEntry] = [:]
    private var runningPrompts: [String: Task<String, Error>] = [:]
    private var promptRequestToSession: [JSONRPCID: String] = [:]
    private var protocolCancelledSessions: Set<String> = []

    public init(
        sessionFactory: @escaping SessionFactory,
        agentInfo: ACPImplementationInfo,
        capabilities: ACPAgentCapabilities,
        authMethods: [ACPAuthMethod] = [],
        authenticationHandler: AuthenticationHandler? = nil,
        options: Options = .init(),
        permissionRequester: PermissionRequester? = nil,
        permissionPolicy: (any ACPPermissionPolicy)? = nil,
        notificationSink: @escaping NotificationSink
    ) {
        self.sessionFactory = sessionFactory
        self.agentInfo = agentInfo
        self.capabilities = capabilities
        self.authMethods = authMethods
        self.authenticationHandler = authenticationHandler
        self.options = options
        self.permissionPolicy = permissionPolicy
        if let permissionRequester {
            self.permissionRequester = permissionRequester
        } else if let permissionPolicy {
            self.permissionRequester = { params in
                try await permissionPolicy.evaluate(params)
            }
        } else {
            self.permissionRequester = nil
        }
        self.notificationSink = notificationSink
    }

    public init(
        agentSessionFactory: @escaping @Sendable () throws -> SKIAgentSession,
        agentInfo: ACPImplementationInfo,
        capabilities: ACPAgentCapabilities,
        authMethods: [ACPAuthMethod] = [],
        authenticationHandler: AuthenticationHandler? = nil,
        options: Options = .init(),
        permissionRequester: PermissionRequester? = nil,
        permissionPolicy: (any ACPPermissionPolicy)? = nil,
        notificationSink: @escaping NotificationSink
    ) {
        self.init(
            sessionFactory: {
                try agentSessionFactory()
            },
            agentInfo: agentInfo,
            capabilities: capabilities,
            authMethods: authMethods,
            authenticationHandler: authenticationHandler,
            options: options,
            permissionRequester: permissionRequester,
            permissionPolicy: permissionPolicy,
            notificationSink: notificationSink
        )
    }

    public func handle(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        pruneExpiredSessionsIfNeeded()

        do {
            switch request.method {
            case ACPMethods.initialize:
                let params = try ACPCodec.decodeParams(request.params, as: ACPInitializeParams.self)
                guard params.protocolVersion == 1 else {
                    throw ACPAgentServiceError.invalidParams("Unsupported protocolVersion: \(params.protocolVersion), expected: 1")
                }
                let result = ACPInitializeResult(
                    protocolVersion: 1,
                    agentCapabilities: capabilities,
                    agentInfo: agentInfo,
                    authMethods: authMethods
                )
                let value = try ACPCodec.encodeParams(result)
                return JSONRPCResponse(id: request.id, result: value)

            case ACPMethods.authenticate:
                guard !authMethods.isEmpty else {
                    throw ACPAgentServiceError.methodNotFound(ACPMethods.authenticate)
                }
                let params = try ACPCodec.decodeParams(request.params, as: ACPAuthenticateParams.self)
                guard authMethods.contains(where: { $0.id == params.methodId }) else {
                    throw ACPAgentServiceError.invalidParams("Unsupported auth methodId: \(params.methodId)")
                }
                try await authenticationHandler?(params)
                return JSONRPCResponse(id: request.id, result: try ACPCodec.encodeParams(ACPAuthenticateResult()))

            case ACPMethods.logout:
                guard capabilities.authCapabilities.logout != nil else {
                    throw ACPAgentServiceError.methodNotFound(ACPMethods.logout)
                }
                if let permissionPolicy {
                    for sessionId in sessions.keys {
                        await permissionPolicy.clear(sessionId: sessionId)
                    }
                }
                sessions.removeAll()
                runningPrompts.values.forEach { $0.cancel() }
                runningPrompts.removeAll()
                promptRequestToSession.removeAll()
                protocolCancelledSessions.removeAll()
                return JSONRPCResponse(id: request.id, result: try ACPCodec.encodeParams(ACPLogoutResult()))

            case ACPMethods.sessionNew:
                let params = try ACPCodec.decodeParams(request.params, as: ACPSessionNewParams.self)
                let sessionID = "sess_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                sessions[sessionID] = SessionEntry(
                    session: try sessionFactory(),
                    cwd: params.cwd,
                    title: nil,
                    updatedAt: iso8601TimestampNow(),
                    currentModeId: "default",
                    availableModes: [
                        .init(id: "default", name: "Default")
                    ],
                    currentModelId: "default",
                    availableModels: [
                        .init(modelId: "default", name: "Default"),
                        .init(modelId: "gpt-5", name: "GPT-5")
                    ],
                    configOptions: [],
                    lastTouchedNanos: currentMonotonicNanos()
                )
                let result = ACPSessionNewResult(
                    sessionId: sessionID,
                    modes: .init(currentModeId: "default", availableModes: [.init(id: "default", name: "Default")]),
                    models: .init(
                        currentModelId: "default",
                        availableModels: [
                            .init(modelId: "default", name: "Default"),
                            .init(modelId: "gpt-5", name: "GPT-5")
                        ]
                    ),
                    configOptions: []
                )
                return JSONRPCResponse(id: request.id, result: try ACPCodec.encodeParams(result))

            case ACPMethods.sessionList:
                guard capabilities.sessionCapabilities.list != nil else {
                    throw ACPAgentServiceError.methodNotFound(ACPMethods.sessionList)
                }
                let params = try ACPCodec.decodeParams(request.params, as: ACPSessionListParams.self)
                let values = sessions
                    .sorted(by: {
                        if $0.value.lastTouchedNanos == $1.value.lastTouchedNanos {
                            return $0.key < $1.key
                        }
                        return $0.value.lastTouchedNanos > $1.value.lastTouchedNanos
                    })
                    .map { (sessionID, entry) in
                    ACPSessionInfo(
                        sessionId: sessionID,
                        cwd: entry.cwd,
                        title: entry.title,
                        updatedAt: entry.updatedAt
                    )
                }
                let filtered = params.cwd.map { cwd in
                    values.filter { $0.cwd == cwd }
                } ?? values
                let offset: Int
                if let cursor = params.cursor {
                    guard let decoded = decodeSessionListCursor(cursor) else {
                        throw ACPAgentServiceError.invalidParams("Invalid cursor")
                    }
                    offset = decoded
                } else {
                    offset = 0
                }
                guard offset >= 0, offset <= filtered.count else {
                    throw ACPAgentServiceError.invalidParams("Invalid cursor")
                }
                let end = min(filtered.count, offset + options.sessionListPageSize)
                let page = Array(filtered[offset..<end])
                let nextCursor = end < filtered.count ? encodeSessionListCursor(end) : nil
                return JSONRPCResponse(
                    id: request.id,
                    result: try ACPCodec.encodeParams(ACPSessionListResult(sessions: page, nextCursor: nextCursor))
                )

            case ACPMethods.sessionResume:
                guard capabilities.sessionCapabilities.resume != nil else {
                    throw ACPAgentServiceError.methodNotFound(ACPMethods.sessionResume)
                }
                let params = try ACPCodec.decodeParams(request.params, as: ACPSessionResumeParams.self)
                guard var entry = sessions[params.sessionId] else {
                    throw ACPAgentServiceError.sessionNotFound(params.sessionId)
                }
                entry.cwd = params.cwd
                entry.lastTouchedNanos = currentMonotonicNanos()
                entry.updatedAt = iso8601TimestampNow()
                sessions[params.sessionId] = entry
                return JSONRPCResponse(
                    id: request.id,
                    result: try ACPCodec.encodeParams(
                        ACPSessionResumeResult(
                            modes: .init(
                                currentModeId: entry.currentModeId ?? "default",
                                availableModes: entry.availableModes
                            ),
                            models: .init(
                                currentModelId: entry.currentModelId ?? "default",
                                availableModels: entry.availableModels
                            ),
                            configOptions: entry.configOptions
                        )
                    )
                )

            case ACPMethods.sessionFork:
                guard capabilities.sessionCapabilities.fork != nil else {
                    throw ACPAgentServiceError.methodNotFound(ACPMethods.sessionFork)
                }
                let params = try ACPCodec.decodeParams(request.params, as: ACPSessionForkParams.self)
                guard let sourceEntry = sessions[params.sessionId] else {
                    throw ACPAgentServiceError.sessionNotFound(params.sessionId)
                }
                let sessionID = "sess_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                sessions[sessionID] = SessionEntry(
                    session: try sessionFactory(),
                    cwd: params.cwd,
                    title: sourceEntry.title,
                    updatedAt: iso8601TimestampNow(),
                    currentModeId: sourceEntry.currentModeId,
                    availableModes: sourceEntry.availableModes,
                    currentModelId: sourceEntry.currentModelId,
                    availableModels: sourceEntry.availableModels,
                    configOptions: sourceEntry.configOptions,
                    lastTouchedNanos: currentMonotonicNanos()
                )
                return JSONRPCResponse(
                    id: request.id,
                    result: try ACPCodec.encodeParams(
                        ACPSessionForkResult(
                            sessionId: sessionID,
                            modes: .init(
                                currentModeId: sourceEntry.currentModeId ?? "default",
                                availableModes: sourceEntry.availableModes
                            ),
                            models: .init(
                                currentModelId: sourceEntry.currentModelId ?? "default",
                                availableModels: sourceEntry.availableModels
                            ),
                            configOptions: sourceEntry.configOptions
                        )
                    )
                )

            case ACPMethods.sessionDelete:
                guard capabilities.sessionCapabilities.delete != nil else {
                    throw ACPAgentServiceError.methodNotFound(ACPMethods.sessionDelete)
                }
                let params = try ACPCodec.decodeParams(request.params, as: ACPSessionDeleteParams.self)
                sessions[params.sessionId] = nil
                runningPrompts[params.sessionId]?.cancel()
                runningPrompts[params.sessionId] = nil
                await permissionPolicy?.clear(sessionId: params.sessionId)
                return JSONRPCResponse(
                    id: request.id,
                    result: try ACPCodec.encodeParams(ACPSessionDeleteResult())
                )

            case ACPMethods.sessionLoad:
                guard capabilities.loadSession else {
                    throw ACPAgentServiceError.methodNotFound(ACPMethods.sessionLoad)
                }
                let params = try ACPCodec.decodeParams(request.params, as: ACPSessionLoadParams.self)
                guard var entry = sessions[params.sessionId] else {
                    throw ACPAgentServiceError.sessionNotFound(params.sessionId)
                }
                entry.cwd = params.cwd
                sessions[params.sessionId] = entry
                touchSession(params.sessionId)
                let result = ACPSessionLoadResult(
                    modes: .init(
                        currentModeId: entry.currentModeId ?? "default",
                        availableModes: entry.availableModes
                    ),
                    models: .init(
                        currentModelId: entry.currentModelId ?? "default",
                        availableModels: entry.availableModels
                    ),
                    configOptions: entry.configOptions
                )
                return JSONRPCResponse(id: request.id, result: try ACPCodec.encodeParams(result))

            case ACPMethods.sessionSetMode:
                let params = try ACPCodec.decodeParams(request.params, as: ACPSessionSetModeParams.self)
                guard var entry = sessions[params.sessionId] else {
                    throw ACPAgentServiceError.sessionNotFound(params.sessionId)
                }
                entry.currentModeId = params.modeId
                entry.lastTouchedNanos = currentMonotonicNanos()
                entry.updatedAt = iso8601TimestampNow()
                sessions[params.sessionId] = entry

                let update = ACPSessionUpdateParams(
                    sessionId: params.sessionId,
                    update: .init(sessionUpdate: .currentModeUpdate, currentModeId: params.modeId)
                )
                let notification = JSONRPCNotification(method: ACPMethods.sessionUpdate, params: try ACPCodec.encodeParams(update))
                await notificationSink(notification)
                return JSONRPCResponse(id: request.id, result: try ACPCodec.encodeParams(ACPSessionSetModeResult()))

            case ACPMethods.sessionSetModel:
                let params = try ACPCodec.decodeParams(request.params, as: ACPSessionSetModelParams.self)
                guard var entry = sessions[params.sessionId] else {
                    throw ACPAgentServiceError.sessionNotFound(params.sessionId)
                }
                guard entry.availableModels.contains(where: { $0.modelId == params.modelId }) else {
                    throw ACPAgentServiceError.invalidParams("Unsupported modelId: \(params.modelId)")
                }
                entry.currentModelId = params.modelId
                entry.lastTouchedNanos = currentMonotonicNanos()
                entry.updatedAt = iso8601TimestampNow()
                sessions[params.sessionId] = entry
                return JSONRPCResponse(id: request.id, result: try ACPCodec.encodeParams(ACPSessionSetModelResult()))

            case ACPMethods.sessionSetConfigOption:
                let params = try ACPCodec.decodeParams(request.params, as: ACPSessionSetConfigOptionParams.self)
                guard var entry = sessions[params.sessionId] else {
                    throw ACPAgentServiceError.sessionNotFound(params.sessionId)
                }
                let optionName = params.configId.replacingOccurrences(of: "_", with: " ").capitalized
                let option = ACPSessionConfigOption(
                    id: params.configId,
                    name: optionName,
                    category: .other,
                    currentValue: params.value,
                    options: .ungrouped([.init(value: params.value, name: params.value.capitalized)])
                )
                if let index = entry.configOptions.firstIndex(where: { $0.id == params.configId }) {
                    entry.configOptions[index] = option
                } else {
                    entry.configOptions.append(option)
                }
                entry.lastTouchedNanos = currentMonotonicNanos()
                entry.updatedAt = iso8601TimestampNow()
                sessions[params.sessionId] = entry

                let result = ACPSessionSetConfigOptionResult(configOptions: entry.configOptions)
                let update = ACPSessionUpdateParams(
                    sessionId: params.sessionId,
                    update: .init(sessionUpdate: .configOptionUpdate, configOptions: entry.configOptions)
                )
                let notification = JSONRPCNotification(method: ACPMethods.sessionUpdate, params: try ACPCodec.encodeParams(update))
                await notificationSink(notification)
                return JSONRPCResponse(id: request.id, result: try ACPCodec.encodeParams(result))

            case ACPMethods.sessionPrompt:
                let params = try ACPCodec.decodeParams(request.params, as: ACPSessionPromptParams.self)
                guard let entry = sessions[params.sessionId] else {
                    throw ACPAgentServiceError.sessionNotFound(params.sessionId)
                }
                let session = entry.session
                guard runningPrompts[params.sessionId] == nil else {
                    throw ACPAgentServiceError.invalidParams("Prompt already running for session: \(params.sessionId)")
                }
                touchSession(params.sessionId)

                if let permissionRequester {
                    let permissionRequest = ACPSessionPermissionRequestParams(
                        sessionId: params.sessionId,
                        toolCall: .init(toolCallId: "call_\(UUID().uuidString)", title: "Execute session prompt"),
                        options: [
                            .init(optionId: "allow_once", name: "Allow once", kind: .allowOnce),
                            .init(optionId: "allow_always", name: "Always allow", kind: .allowAlways),
                            .init(optionId: "reject_once", name: "Reject once", kind: .rejectOnce),
                            .init(optionId: "reject_always", name: "Always reject", kind: .rejectAlways),
                        ]
                    )
                    let decision = try await permissionRequester(permissionRequest)
                    if let permissionPolicy {
                        await permissionPolicy.remember(permissionRequest, decision: decision)
                    }
                    let shouldAllow: Bool
                    switch decision.outcome {
                    case .cancelled:
                        shouldAllow = false
                    case .selected(let selected):
                        shouldAllow = selected.optionId.hasPrefix("allow")
                    }
                    guard shouldAllow else {
                        let result = ACPSessionPromptResult(stopReason: .cancelled)
                        return JSONRPCResponse(id: request.id, result: try ACPCodec.encodeParams(result))
                    }
                }

                let text = params.prompt.compactMap(\.text).joined(separator: "\n")
                let toolCallID = "call_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                promptRequestToSession[request.id] = params.sessionId
                defer { promptRequestToSession[request.id] = nil }
                let task = Task<String, Error> { try await session.prompt(text) }
                runningPrompts[params.sessionId] = task

                do {
                    let output = try await awaitPrompt(task)
                    runningPrompts[params.sessionId] = nil

                    let availableCommandsNotification = JSONRPCNotification(
                        method: ACPMethods.sessionUpdate,
                        params: try ACPCodec.encodeParams(
                            ACPSessionUpdateParams(
                                sessionId: params.sessionId,
                                update: .init(
                                    sessionUpdate: .availableCommandsUpdate,
                                    availableCommands: [
                                        .init(name: "read_file", description: "Read text file"),
                                        .init(name: "run_terminal", description: "Run terminal command")
                                    ]
                                )
                            )
                        )
                    )
                    await notificationSink(availableCommandsNotification)

                    let planNotification = JSONRPCNotification(
                        method: ACPMethods.sessionUpdate,
                        params: try ACPCodec.encodeParams(
                            ACPSessionUpdateParams(
                                sessionId: params.sessionId,
                                update: .init(
                                    sessionUpdate: .plan,
                                    plan: .init(entries: [
                                        .init(content: "Analyze prompt", status: "completed", priority: "high"),
                                        .init(content: "Produce final answer", status: "in_progress", priority: "medium")
                                    ])
                                )
                            )
                        )
                    )
                    await notificationSink(planNotification)

                    let toolCallNotification = JSONRPCNotification(
                        method: ACPMethods.sessionUpdate,
                        params: try ACPCodec.encodeParams(
                            ACPSessionUpdateParams(
                                sessionId: params.sessionId,
                                update: .init(
                                    sessionUpdate: .toolCall,
                                    toolCall: .init(
                                        toolCallId: toolCallID,
                                        title: "language_model_prompt",
                                        kind: .execute,
                                        status: .inProgress,
                                        locations: [.init(path: entry.cwd)]
                                    )
                                )
                            )
                        )
                    )
                    await notificationSink(toolCallNotification)

                    let toolCallUpdateNotification = JSONRPCNotification(
                        method: ACPMethods.sessionUpdate,
                        params: try ACPCodec.encodeParams(
                            ACPSessionUpdateParams(
                                sessionId: params.sessionId,
                                update: .init(
                                    sessionUpdate: .toolCallUpdate,
                                    toolCall: .init(
                                        toolCallId: toolCallID,
                                        status: .completed
                                    )
                                )
                            )
                        )
                    )
                    await notificationSink(toolCallUpdateNotification)

                    let update = ACPSessionUpdateParams(
                        sessionId: params.sessionId,
                        update: ACPSessionUpdatePayload(
                            sessionUpdate: .agentMessageChunk,
                            content: ACPSessionUpdateContent(type: "text", text: output)
                        )
                    )
                    let notification = JSONRPCNotification(method: ACPMethods.sessionUpdate, params: try ACPCodec.encodeParams(update))
                    await notificationSink(notification)

                    if options.autoSessionInfoUpdateOnFirstPrompt,
                       var sessionEntry = sessions[params.sessionId],
                       sessionEntry.title == nil,
                       let generatedTitle = generateSessionTitle(from: text) {
                        sessionEntry.title = generatedTitle
                        sessionEntry.updatedAt = iso8601TimestampNow()
                        sessionEntry.lastTouchedNanos = currentMonotonicNanos()
                        sessions[params.sessionId] = sessionEntry
                        let infoUpdate = ACPSessionUpdateParams(
                            sessionId: params.sessionId,
                            update: .init(
                                sessionUpdate: .sessionInfoUpdate,
                                sessionInfoUpdate: .init(
                                    title: generatedTitle,
                                    updatedAt: sessionEntry.updatedAt
                                )
                            )
                        )
                        let infoNotification = JSONRPCNotification(
                            method: ACPMethods.sessionUpdate,
                            params: try ACPCodec.encodeParams(infoUpdate)
                        )
                        await notificationSink(infoNotification)
                    }

                    let result = ACPSessionPromptResult(stopReason: .endTurn)
                    return JSONRPCResponse(id: request.id, result: try ACPCodec.encodeParams(result))
                } catch is CancellationError {
                    runningPrompts[params.sessionId] = nil
                    if protocolCancelledSessions.remove(params.sessionId) != nil {
                        return errorResponse(ACPAgentServiceError.requestCancelled, id: request.id)
                    }
                    let result = ACPSessionPromptResult(stopReason: .cancelled)
                    return JSONRPCResponse(id: request.id, result: try ACPCodec.encodeParams(result))
                } catch let error as ACPAgentServiceError where error == .promptTimedOut {
                    runningPrompts[params.sessionId] = nil
                    return errorResponse(error, id: request.id)
                }

            default:
                throw ACPAgentServiceError.methodNotFound(request.method)
            }
        } catch {
            return errorResponse(error, id: request.id)
        }
    }

    public func handleCancel(_ notification: JSONRPCNotification) async {
        if notification.method == ACPMethods.sessionCancel {
            guard let params = try? ACPCodec.decodeParams(notification.params, as: ACPSessionCancelParams.self) else { return }
            runningPrompts[params.sessionId]?.cancel()
            runningPrompts[params.sessionId] = nil
            promptRequestToSession = promptRequestToSession.filter { $0.value != params.sessionId }
            protocolCancelledSessions.remove(params.sessionId)
            return
        }

        if notification.method == ACPMethods.cancelRequest {
            guard let params = try? ACPCodec.decodeParams(notification.params, as: ACPCancelRequestParams.self) else { return }
            guard let sessionId = promptRequestToSession.removeValue(forKey: params.requestId) else { return }
            protocolCancelledSessions.insert(sessionId)
            runningPrompts[sessionId]?.cancel()
            runningPrompts[sessionId] = nil
        }
    }

    private func awaitPrompt(_ task: Task<String, Error>) async throws -> String {
        guard let timeout = options.promptTimeoutNanoseconds else {
            return try await task.value
        }

        enum Outcome {
            case value(String)
            case timeout
        }

        return try await withThrowingTaskGroup(of: Outcome.self) { group in
            group.addTask {
                let value = try await task.value
                return .value(value)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeout)
                return .timeout
            }

            guard let first = try await group.next() else {
                throw ACPAgentServiceError.promptTimedOut
            }
            group.cancelAll()
            switch first {
            case .value(let value):
                return value
            case .timeout:
                task.cancel()
                throw ACPAgentServiceError.promptTimedOut
            }
        }
    }

    private func errorResponse(_ error: Error, id: JSONRPCID) -> JSONRPCResponse {
        let rpcError: JSONRPCErrorObject
        if let serviceError = error as? ACPAgentServiceError {
            switch serviceError {
            case .methodNotFound:
                rpcError = .init(code: JSONRPCErrorCode.methodNotFound, message: serviceError.localizedDescription)
            case .invalidParams, .sessionNotFound:
                rpcError = .init(code: JSONRPCErrorCode.invalidParams, message: serviceError.localizedDescription)
            case .promptTimedOut:
                rpcError = .init(code: JSONRPCErrorCode.internalError, message: serviceError.localizedDescription)
            case .requestCancelled:
                rpcError = .init(code: JSONRPCErrorCode.requestCancelled, message: serviceError.localizedDescription)
            }
        } else if let nsError = error as NSError?, nsError.domain == "ACPCodec" || error is DecodingError {
            rpcError = .init(code: JSONRPCErrorCode.invalidParams, message: error.localizedDescription)
        } else {
            rpcError = .init(code: JSONRPCErrorCode.internalError, message: error.localizedDescription)
        }
        return JSONRPCResponse(id: id, error: rpcError)
    }

    private func touchSession(_ id: String) {
        guard var entry = sessions[id] else { return }
        entry.lastTouchedNanos = currentMonotonicNanos()
        entry.updatedAt = iso8601TimestampNow()
        sessions[id] = entry
    }

    private func encodeSessionListCursor(_ offset: Int) -> String {
        Data("v1:\(offset)".utf8).base64EncodedString()
    }

    private func decodeSessionListCursor(_ cursor: String) -> Int? {
        guard let data = Data(base64Encoded: cursor),
              let text = String(data: data, encoding: .utf8),
              text.hasPrefix("v1:") else {
            return nil
        }
        return Int(text.dropFirst(3))
    }

    private func pruneExpiredSessionsIfNeeded() {
        guard let ttl = options.sessionTTLNanos else { return }
        let now = currentMonotonicNanos()
        sessions = sessions.filter { _, entry in
            now &- entry.lastTouchedNanos <= ttl
        }
    }

    private func currentMonotonicNanos() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private func iso8601TimestampNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func generateSessionTitle(from promptText: String) -> String? {
        let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        return String(firstLine.prefix(80))
    }
}

extension ACPAgentServiceError: Equatable {}
