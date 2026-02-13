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

/// Non-ACP extension event for local observability.
/// This type is not part of ACP JSON-RPC schema and must not be serialized as protocol payload.
public struct ACPAgentTelemetryEvent: Sendable, Equatable {
    public var name: String
    public var sessionId: String?
    public var requestId: JSONRPCID?
    public var attributes: [String: String]
    public var timestamp: String

    public init(
        name: String,
        sessionId: String? = nil,
        requestId: JSONRPCID? = nil,
        attributes: [String: String] = [:],
        timestamp: String
    ) {
        self.name = name
        self.sessionId = sessionId
        self.requestId = requestId
        self.attributes = attributes
        self.timestamp = timestamp
    }
}

public actor ACPAgentService {
    public struct Options: Sendable {
        public struct PromptExecution: Sendable, Equatable {
            public var enableStateUpdates: Bool
            public var maxRetries: Int
            public var retryBaseDelayNanoseconds: UInt64

            public init(
                enableStateUpdates: Bool = false,
                maxRetries: Int = 0,
                retryBaseDelayNanoseconds: UInt64 = 100_000_000
            ) {
                self.enableStateUpdates = enableStateUpdates
                self.maxRetries = max(0, maxRetries)
                self.retryBaseDelayNanoseconds = retryBaseDelayNanoseconds
            }
        }

        public struct SessionPersistence: Sendable, Equatable {
            public var directoryURL: URL
            public var configuration: SKITranscript.JSONLPersistenceConfiguration

            public init(
                directoryURL: URL,
                configuration: SKITranscript.JSONLPersistenceConfiguration = .init()
            ) {
                self.directoryURL = directoryURL
                self.configuration = configuration
            }
        }

        public var promptTimeoutNanoseconds: UInt64?
        public var sessionTTLNanos: UInt64?
        public var sessionListPageSize: Int
        public var autoSessionInfoUpdateOnFirstPrompt: Bool
        public var sessionPersistence: SessionPersistence?
        public var promptExecution: PromptExecution

        public init(
            promptTimeoutNanoseconds: UInt64? = nil,
            sessionTTLNanos: UInt64? = nil,
            sessionListPageSize: Int = 50,
            autoSessionInfoUpdateOnFirstPrompt: Bool = false,
            sessionPersistence: SessionPersistence? = nil,
            promptExecution: PromptExecution = .init()
        ) {
            self.promptTimeoutNanoseconds = promptTimeoutNanoseconds
            self.sessionTTLNanos = sessionTTLNanos
            self.sessionListPageSize = max(1, sessionListPageSize)
            self.autoSessionInfoUpdateOnFirstPrompt = autoSessionInfoUpdateOnFirstPrompt
            self.sessionPersistence = sessionPersistence
            self.promptExecution = promptExecution
        }
    }

    public typealias SessionFactory = @Sendable () throws -> any ACPAgentSession
    public typealias NotificationSink = @Sendable (JSONRPCNotification) async -> Void
    /// Non-ACP extension hook for metrics/logging pipelines.
    /// Keep protocol behavior unchanged when sink is nil.
    public typealias TelemetrySink = @Sendable (ACPAgentTelemetryEvent) async -> Void
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
    private let telemetrySink: TelemetrySink?

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
        telemetrySink: TelemetrySink? = nil,
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
        self.telemetrySink = telemetrySink
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
        telemetrySink: TelemetrySink? = nil,
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
            telemetrySink: telemetrySink,
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
                let session = try sessionFactory()
                try await configureSessionPersistenceIfNeeded(session: session, sessionId: sessionID)
                sessions[sessionID] = SessionEntry(
                    session: session,
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
                await emitTelemetry(
                    name: "session_new",
                    sessionId: sessionID,
                    requestId: request.id,
                    attributes: ["cwd": params.cwd]
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
                let snapshot = try await sourceEntry.session.snapshotEntries()
                let forkedSession = try sessionFactory()
                try await forkedSession.restoreEntries(snapshot)
                let sessionID = "sess_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                try await configureSessionPersistenceIfNeeded(session: forkedSession, sessionId: sessionID)
                sessions[sessionID] = SessionEntry(
                    session: forkedSession,
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
                await emitTelemetry(
                    name: "session_delete",
                    sessionId: params.sessionId,
                    requestId: request.id
                )
                return JSONRPCResponse(
                    id: request.id,
                    result: try ACPCodec.encodeParams(ACPSessionDeleteResult())
                )

            case ACPMethods.sessionLoad:
                guard capabilities.loadSession else {
                    throw ACPAgentServiceError.methodNotFound(ACPMethods.sessionLoad)
                }
                let params = try ACPCodec.decodeParams(request.params, as: ACPSessionLoadParams.self)
                let entry: SessionEntry
                if var loaded = sessions[params.sessionId] {
                    loaded.cwd = params.cwd
                    sessions[params.sessionId] = loaded
                    entry = loaded
                } else {
                    guard let restored = try await restoreSessionFromPersistenceIfPresent(
                        sessionId: params.sessionId,
                        cwd: params.cwd
                    ) else {
                        throw ACPAgentServiceError.sessionNotFound(params.sessionId)
                    }
                    sessions[params.sessionId] = restored
                    entry = restored
                }
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
                await emitTelemetry(
                    name: "session_load",
                    sessionId: params.sessionId,
                    requestId: request.id,
                    attributes: ["cwd": params.cwd]
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

                let event = SKITranscript.sessionUpdateEvent(name: "current_mode_update")
                if let update = sessionUpdatePayload(
                    from: event,
                    sessionId: params.sessionId,
                    cwd: entry.cwd,
                    currentModeId: params.modeId
                ) {
                    try await emitSessionUpdate(update)
                }
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
                let event = SKITranscript.sessionUpdateEvent(name: "config_option_update")
                if let update = sessionUpdatePayload(
                    from: event,
                    sessionId: params.sessionId,
                    cwd: entry.cwd,
                    configOptions: entry.configOptions
                ) {
                    try await emitSessionUpdate(update)
                }
                return JSONRPCResponse(id: request.id, result: try ACPCodec.encodeParams(result))

            case ACPMethods.sessionPrompt:
                let params = try ACPCodec.decodeParams(request.params, as: ACPSessionPromptParams.self)
                guard let entry = sessions[params.sessionId] else {
                    throw ACPAgentServiceError.sessionNotFound(params.sessionId)
                }
                await emitTelemetry(
                    name: "prompt_requested",
                    sessionId: params.sessionId,
                    requestId: request.id
                )
                try await emitExecutionStateIfNeeded(
                    sessionId: params.sessionId,
                    state: .queued
                )
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
                        await emitTelemetry(
                            name: "prompt_permission_denied",
                            sessionId: params.sessionId,
                            requestId: request.id
                        )
                        try await emitExecutionStateIfNeeded(
                            sessionId: params.sessionId,
                            state: .cancelled,
                            message: "Permission denied"
                        )
                        let result = ACPSessionPromptResult(stopReason: .cancelled)
                        return JSONRPCResponse(id: request.id, result: try ACPCodec.encodeParams(result))
                    }
                }

                let text = params.prompt.compactMap(\.text).joined(separator: "\n")
                let toolCallID = "call_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                promptRequestToSession[request.id] = params.sessionId
                defer { promptRequestToSession[request.id] = nil }
                try await emitExecutionStateIfNeeded(
                    sessionId: params.sessionId,
                    state: .running
                )
                await emitTelemetry(
                    name: "prompt_started",
                    sessionId: params.sessionId,
                    requestId: request.id
                )
                let task = Task<String, Error> {
                    try await self.runPromptWithRetry(
                        session: session,
                        text: text,
                        sessionId: params.sessionId
                    )
                }
                runningPrompts[params.sessionId] = task

                do {
                    let output = try await awaitPrompt(task)
                    runningPrompts[params.sessionId] = nil
                    let syntheticEvents: [SKITranscript.Event] = [
                        SKITranscript.sessionUpdateEvent(name: "available_commands_update"),
                        SKITranscript.sessionUpdateEvent(name: "plan"),
                        .init(kind: .toolCall, toolName: "language_model_prompt", toolCallId: toolCallID),
                        .init(kind: .toolExecutionUpdate, toolName: "language_model_prompt", toolCallId: toolCallID, state: .completed),
                        .init(kind: .message, role: "assistant", content: output),
                    ]
                    for event in syntheticEvents {
                        if let update = sessionUpdatePayload(from: event, sessionId: params.sessionId, cwd: entry.cwd) {
                            try await emitSessionUpdate(update)
                        }
                    }

                    if options.autoSessionInfoUpdateOnFirstPrompt,
                       var sessionEntry = sessions[params.sessionId],
                       sessionEntry.title == nil,
                       let generatedTitle = generateSessionTitle(from: text) {
                        sessionEntry.title = generatedTitle
                        sessionEntry.updatedAt = iso8601TimestampNow()
                        sessionEntry.lastTouchedNanos = currentMonotonicNanos()
                        sessions[params.sessionId] = sessionEntry
                        let event = SKITranscript.sessionUpdateEvent(name: "session_info_update")
                        if let update = sessionUpdatePayload(
                            from: event,
                            sessionId: params.sessionId,
                            cwd: sessionEntry.cwd,
                            sessionInfoUpdate: .init(
                                title: generatedTitle,
                                updatedAt: sessionEntry.updatedAt
                            )
                        ) {
                            try await emitSessionUpdate(update)
                        }
                    }

                    try await emitExecutionStateIfNeeded(
                        sessionId: params.sessionId,
                        state: .completed
                    )
                    await emitTelemetry(
                        name: "prompt_completed",
                        sessionId: params.sessionId,
                        requestId: request.id
                    )
                    let result = ACPSessionPromptResult(stopReason: .endTurn)
                    return JSONRPCResponse(id: request.id, result: try ACPCodec.encodeParams(result))
                } catch is CancellationError {
                    runningPrompts[params.sessionId] = nil
                    try await emitExecutionStateIfNeeded(
                        sessionId: params.sessionId,
                        state: .cancelled
                    )
                    await emitTelemetry(
                        name: "prompt_cancelled",
                        sessionId: params.sessionId,
                        requestId: request.id
                    )
                    if protocolCancelledSessions.remove(params.sessionId) != nil {
                        return errorResponse(ACPAgentServiceError.requestCancelled, id: request.id)
                    }
                    let result = ACPSessionPromptResult(stopReason: .cancelled)
                    return JSONRPCResponse(id: request.id, result: try ACPCodec.encodeParams(result))
                } catch let error as ACPAgentServiceError where error == .promptTimedOut {
                    runningPrompts[params.sessionId] = nil
                    try await emitExecutionStateIfNeeded(
                        sessionId: params.sessionId,
                        state: .timedOut
                    )
                    await emitTelemetry(
                        name: "prompt_timed_out",
                        sessionId: params.sessionId,
                        requestId: request.id
                    )
                    return errorResponse(error, id: request.id)
                } catch {
                    runningPrompts[params.sessionId] = nil
                    try await emitExecutionStateIfNeeded(
                        sessionId: params.sessionId,
                        state: .failed,
                        message: error.localizedDescription
                    )
                    await emitTelemetry(
                        name: "prompt_failed",
                        sessionId: params.sessionId,
                        requestId: request.id,
                        attributes: ["error": error.localizedDescription]
                    )
                    throw error
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

    private func sessionPersistenceFileURL(sessionId: String) -> URL? {
        guard let persistence = options.sessionPersistence else { return nil }
        return persistence.directoryURL
            .appendingPathComponent("\(sessionId).jsonl", isDirectory: false)
    }

    private func configureSessionPersistenceIfNeeded(
        session: any ACPAgentSession,
        sessionId: String
    ) async throws {
        guard let persistence = options.sessionPersistence else { return }
        guard let persistable = session as? any ACPPersistableAgentSession else { return }
        guard let fileURL = sessionPersistenceFileURL(sessionId: sessionId) else { return }
        try await persistable.enableJSONLPersistence(
            fileURL: fileURL,
            configuration: persistence.configuration
        )
    }

    private func restoreSessionFromPersistenceIfPresent(
        sessionId: String,
        cwd: String
    ) async throws -> SessionEntry? {
        guard let fileURL = sessionPersistenceFileURL(sessionId: sessionId) else { return nil }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let session = try sessionFactory()
        try await configureSessionPersistenceIfNeeded(session: session, sessionId: sessionId)
        return SessionEntry(
            session: session,
            cwd: cwd,
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

    private func sessionUpdatePayload(
        from event: SKITranscript.Event,
        sessionId: String,
        cwd: String,
        currentModeId: String? = nil,
        configOptions: [ACPSessionConfigOption] = [],
        sessionInfoUpdate: ACPSessionInfoUpdate? = nil
    ) -> ACPSessionUpdateParams? {
        switch event.kind {
        case .message:
            guard event.role == "assistant" else { return nil }
            return ACPSessionUpdateParams(
                sessionId: sessionId,
                update: .init(update: .agentMessageChunk(.text(event.content ?? "")))
            )
        case .toolCall:
            guard let toolCallId = event.toolCallId else { return nil }
            return ACPSessionUpdateParams(
                sessionId: sessionId,
                update: .init(
                    update: .toolCall(
                        .init(
                            toolCallId: toolCallId,
                            title: event.toolName ?? "tool_call",
                            kind: .execute,
                            status: .inProgress,
                            locations: [.init(path: cwd)]
                        )
                    )
                )
            )
        case .toolResult:
            guard let toolCallId = event.toolCallId else { return nil }
            return ACPSessionUpdateParams(
                sessionId: sessionId,
                update: .init(
                    update: .toolCallUpdate(
                        .init(
                            toolCallId: toolCallId,
                            status: .completed
                        )
                    )
                )
            )
        case .toolExecutionUpdate:
            guard let toolCallId = event.toolCallId else { return nil }
            let status: ACPToolCallStatus
            switch event.state {
            case .started:
                status = .inProgress
            case .completed:
                status = .completed
            case .failed:
                status = .failed
            case .none:
                status = .pending
            }
            return ACPSessionUpdateParams(
                sessionId: sessionId,
                update: .init(
                    update: .toolCallUpdate(
                        .init(
                            toolCallId: toolCallId,
                            status: status
                        )
                    )
                )
            )
        case .sessionUpdate:
            guard let name = event.sessionUpdateName else { return nil }
            switch name {
            case "available_commands_update":
                return ACPSessionUpdateParams(
                    sessionId: sessionId,
                    update: .init(
                        update: .availableCommandsUpdate([
                            .init(name: "read_file", description: "Read text file"),
                            .init(name: "run_terminal", description: "Run terminal command"),
                        ])
                    )
                )
            case "plan":
                return ACPSessionUpdateParams(
                    sessionId: sessionId,
                    update: .init(
                        update: .plan(
                            .init(entries: [
                                .init(content: "Analyze prompt", status: "completed", priority: "high"),
                                .init(content: "Produce final answer", status: "in_progress", priority: "medium"),
                            ])
                        )
                    )
                )
            case "current_mode_update":
                return ACPSessionUpdateParams(
                    sessionId: sessionId,
                    update: .init(
                        update: .currentModeUpdate(currentModeId ?? "")
                    )
                )
            case "config_option_update":
                return ACPSessionUpdateParams(
                    sessionId: sessionId,
                    update: .init(
                        update: .configOptionUpdate(configOptions)
                    )
                )
            case "session_info_update":
                return ACPSessionUpdateParams(
                    sessionId: sessionId,
                    update: .init(
                        update: .sessionInfoUpdate(
                            sessionInfoUpdate ?? .init()
                        )
                    )
                )
            default:
                return nil
            }
        }
    }

    private func emitSessionUpdate(_ params: ACPSessionUpdateParams) async throws {
        let notification = JSONRPCNotification(
            method: ACPMethods.sessionUpdate,
            params: try ACPCodec.encodeParams(params)
        )
        await notificationSink(notification)
    }

    private func emitExecutionStateIfNeeded(
        sessionId: String,
        state: ACPExecutionState,
        attempt: Int? = nil,
        message: String? = nil
    ) async throws {
        guard options.promptExecution.enableStateUpdates else { return }
        try await emitSessionUpdate(
            .init(
                sessionId: sessionId,
                update: .init(
                    sessionUpdate: .executionStateUpdate,
                    executionStateUpdate: .init(
                        state: state,
                        attempt: attempt,
                        message: message
                    )
                )
            )
        )
    }

    private func runPromptWithRetry(
        session: any ACPAgentSession,
        text: String,
        sessionId: String
    ) async throws -> String {
        let maxRetries = options.promptExecution.maxRetries
        var attempt = 0
        while true {
            do {
                return try await session.prompt(text)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ACPAgentServiceError where error == .promptTimedOut {
                throw error
            } catch {
                guard attempt < maxRetries else {
                    throw error
                }
                attempt += 1
                try await emitExecutionStateIfNeeded(
                    sessionId: sessionId,
                    state: .retrying,
                    attempt: attempt,
                    message: error.localizedDescription
                )
                try await emitRetryUpdate(
                    sessionId: sessionId,
                    attempt: attempt,
                    maxAttempts: maxRetries + 1,
                    reason: error.localizedDescription
                )
                await emitTelemetry(
                    name: "prompt_retry",
                    sessionId: sessionId,
                    attributes: [
                        "attempt": "\(attempt)",
                        "maxAttempts": "\(maxRetries + 1)",
                        "reason": error.localizedDescription
                    ]
                )
                let delay = options.promptExecution.retryBaseDelayNanoseconds * UInt64(attempt)
                if delay > 0 {
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }
    }

    private func emitRetryUpdate(
        sessionId: String,
        attempt: Int,
        maxAttempts: Int,
        reason: String?
    ) async throws {
        try await emitSessionUpdate(
            .init(
                sessionId: sessionId,
                update: .init(
                    sessionUpdate: .retryUpdate,
                    retryUpdate: .init(
                        attempt: attempt,
                        maxAttempts: maxAttempts,
                        reason: reason
                    )
                )
            )
        )
    }

    private func emitTelemetry(
        name: String,
        sessionId: String? = nil,
        requestId: JSONRPCID? = nil,
        attributes: [String: String] = [:]
    ) async {
        guard let telemetrySink else { return }
        await telemetrySink(
            .init(
                name: name,
                sessionId: sessionId,
                requestId: requestId,
                attributes: attributes,
                timestamp: iso8601TimestampNow()
            )
        )
    }
}

extension ACPAgentServiceError: Equatable {}
