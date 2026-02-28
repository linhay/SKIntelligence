import Foundation
import SKIACP
import SKIACPTransport
import SKIACP
@preconcurrency import STJSON

public enum ACPClientServiceError: Error, LocalizedError {
    case requestTimeout(method: String)
    case rpcError(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .requestTimeout(let method):
            return "Request timed out: \(method)"
        case .rpcError(_, let message):
            return message
        }
    }
}

public actor ACPClientService {
    public typealias NotificationHandler = @Sendable (JSONRPC.Request) async -> Void
    public typealias PermissionRequestHandler = @Sendable (ACPSessionPermissionRequestParams) async throws -> ACPSessionPermissionRequestResult
    public typealias ReadTextFileHandler = @Sendable (ACPReadTextFileParams) async throws -> ACPReadTextFileResult
    public typealias WriteTextFileHandler = @Sendable (ACPWriteTextFileParams) async throws -> ACPWriteTextFileResult
    public typealias TerminalCreateHandler = @Sendable (ACPTerminalCreateParams) async throws -> ACPTerminalCreateResult
    public typealias TerminalOutputHandler = @Sendable (ACPTerminalRefParams) async throws -> ACPTerminalOutputResult
    public typealias TerminalWaitForExitHandler = @Sendable (ACPTerminalRefParams) async throws -> ACPTerminalWaitForExitResult
    public typealias TerminalKillHandler = @Sendable (ACPTerminalRefParams) async throws -> ACPTerminalKillResult
    public typealias TerminalReleaseHandler = @Sendable (ACPTerminalRefParams) async throws -> ACPTerminalReleaseResult

    private let transport: any ACPTransport
    private let requestTimeoutNanoseconds: UInt64?
    private var nextID: Int = 1
    private var pending: [JSONRPC.ID: CheckedContinuation<JSONRPC.Response, Error>] = [:]
    private var timeoutTasks: [JSONRPC.ID: Task<Void, Never>] = [:]
    private var pendingMethods: [JSONRPC.ID: String] = [:]
    private var receiveTask: Task<Void, Never>?

    public var onNotification: NotificationHandler?
    public var onPermissionRequest: PermissionRequestHandler?
    public var onReadTextFile: ReadTextFileHandler?
    public var onWriteTextFile: WriteTextFileHandler?
    public var onTerminalCreate: TerminalCreateHandler?
    public var onTerminalOutput: TerminalOutputHandler?
    public var onTerminalWaitForExit: TerminalWaitForExitHandler?
    public var onTerminalKill: TerminalKillHandler?
    public var onTerminalRelease: TerminalReleaseHandler?

    public init(transport: any ACPTransport, requestTimeoutNanoseconds: UInt64? = nil) {
        self.transport = transport
        self.requestTimeoutNanoseconds = requestTimeoutNanoseconds
    }

    deinit {
        receiveTask?.cancel()
    }

    public func connect() async throws {
        try await transport.connect()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop()
        }
    }

    public func close() async {
        receiveTask?.cancel()
        receiveTask = nil
        await transport.close()

        let continuations = pending
        pending.removeAll()
        let timeoutTasks = timeoutTasks
        self.timeoutTasks.removeAll()
        pendingMethods.removeAll()
        timeoutTasks.values.forEach { $0.cancel() }
        continuations.values.forEach { $0.resume(throwing: ACPTransportError.eof) }
    }

    public func setNotificationHandler(_ handler: NotificationHandler?) {
        self.onNotification = handler
    }

    public func setPermissionRequestHandler(_ handler: PermissionRequestHandler?) {
        self.onPermissionRequest = handler
    }

    public func setReadTextFileHandler(_ handler: ReadTextFileHandler?) {
        self.onReadTextFile = handler
    }

    public func setWriteTextFileHandler(_ handler: WriteTextFileHandler?) {
        self.onWriteTextFile = handler
    }

    public func setTerminalCreateHandler(_ handler: TerminalCreateHandler?) {
        self.onTerminalCreate = handler
    }

    public func setTerminalOutputHandler(_ handler: TerminalOutputHandler?) {
        self.onTerminalOutput = handler
    }

    public func setTerminalWaitForExitHandler(_ handler: TerminalWaitForExitHandler?) {
        self.onTerminalWaitForExit = handler
    }

    public func setTerminalKillHandler(_ handler: TerminalKillHandler?) {
        self.onTerminalKill = handler
    }

    public func setTerminalReleaseHandler(_ handler: TerminalReleaseHandler?) {
        self.onTerminalRelease = handler
    }

    public func initialize(_ params: ACPInitializeParams) async throws -> ACPInitializeResult {
        let response = try await call(method: ACPMethods.initialize, params: params)
        return try ACPCodec.decodeResult(response.result, as: ACPInitializeResult.self)
    }

    public func authenticate(_ params: ACPAuthenticateParams) async throws -> ACPAuthenticateResult {
        let response = try await call(method: ACPMethods.authenticate, params: params)
        return try ACPCodec.decodeResult(response.result, as: ACPAuthenticateResult.self)
    }

    public func logout(_ params: ACPLogoutParams = .init()) async throws -> ACPLogoutResult {
        let response = try await call(method: ACPMethods.logout, params: params)
        return try ACPCodec.decodeResult(response.result, as: ACPLogoutResult.self)
    }

    public func newSession(_ params: ACPSessionNewParams) async throws -> ACPSessionNewResult {
        let response = try await call(method: ACPMethods.sessionNew, params: params)
        return try ACPCodec.decodeResult(response.result, as: ACPSessionNewResult.self)
    }

    public func loadSession(_ params: ACPSessionLoadParams) async throws {
        _ = try await call(method: ACPMethods.sessionLoad, params: params)
    }

    public func prompt(_ params: ACPSessionPromptParams) async throws -> ACPSessionPromptResult {
        let response = try await call(method: ACPMethods.sessionPrompt, params: params)
        return try ACPCodec.decodeResult(response.result, as: ACPSessionPromptResult.self)
    }

    public func listSessions(_ params: ACPSessionListParams = .init()) async throws -> ACPSessionListResult {
        let response = try await call(method: ACPMethods.sessionList, params: params)
        return try ACPCodec.decodeResult(response.result, as: ACPSessionListResult.self)
    }

    public func resumeSession(_ params: ACPSessionResumeParams) async throws -> ACPSessionResumeResult {
        let response = try await call(method: ACPMethods.sessionResume, params: params)
        return try ACPCodec.decodeResult(response.result, as: ACPSessionResumeResult.self)
    }

    public func forkSession(_ params: ACPSessionForkParams) async throws -> ACPSessionForkResult {
        let response = try await call(method: ACPMethods.sessionFork, params: params)
        return try ACPCodec.decodeResult(response.result, as: ACPSessionForkResult.self)
    }

    public func deleteSession(_ params: ACPSessionDeleteParams) async throws -> ACPSessionDeleteResult {
        let response = try await call(method: ACPMethods.sessionDelete, params: params)
        return try ACPCodec.decodeResult(response.result, as: ACPSessionDeleteResult.self)
    }

    public func exportSession(_ params: ACPSessionExportParams) async throws -> ACPSessionExportResult {
        let response = try await call(method: ACPMethods.sessionExport, params: params)
        return try ACPCodec.decodeResult(response.result, as: ACPSessionExportResult.self)
    }

    public func setMode(_ params: ACPSessionSetModeParams) async throws -> ACPSessionSetModeResult {
        let response = try await call(method: ACPMethods.sessionSetMode, params: params)
        return try ACPCodec.decodeResult(response.result, as: ACPSessionSetModeResult.self)
    }

    public func setModel(_ params: ACPSessionSetModelParams) async throws -> ACPSessionSetModelResult {
        let response = try await call(method: ACPMethods.sessionSetModel, params: params)
        return try ACPCodec.decodeResult(response.result, as: ACPSessionSetModelResult.self)
    }

    public func setConfigOption(_ params: ACPSessionSetConfigOptionParams) async throws -> ACPSessionSetConfigOptionResult {
        let response = try await call(method: ACPMethods.sessionSetConfigOption, params: params)
        return try ACPCodec.decodeResult(response.result, as: ACPSessionSetConfigOptionResult.self)
    }

    public func cancel(_ params: ACPSessionCancelParams) async throws {
        let payload = try ACPCodec.encodeParams(params)
        let message = JSONRPC.Request(method: ACPMethods.sessionCancel, params: payload)
        try await transport.send(.notification(message))
    }

    /// Compatibility helper for ACP proposal `session/stop`.
    /// Not part of current ACP stable/unstable method baselines.
    public func stopSession(_ params: ACPSessionCancelParams) async throws -> ACPSessionStopResult {
        let response = try await call(method: ACPMethods.sessionStop, params: params)
        return try ACPCodec.decodeResult(response.result, as: ACPSessionStopResult.self)
    }

    public func cancelRequest(_ params: ACPCancelRequestParams) async throws {
        let payload = try ACPCodec.encodeParams(params)
        let message = JSONRPC.Request(method: ACPMethods.cancelRequest, params: payload)
        try await transport.send(.notification(message))
    }

    public func call<Params: Encodable>(method: String, params: Params) async throws -> JSONRPC.Response {
        let id = JSONRPC.ID.int(nextID)
        nextID += 1

        let payload = try ACPCodec.encodeParams(params)
        let request = JSONRPC.Request(id: id, method: method, params: payload)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            pendingMethods[id] = method
            if let timeout = requestTimeoutNanoseconds {
                timeoutTasks[id] = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: timeout)
                    await self?.timeoutPending(id: id, method: method)
                }
            }
            Task {
                do {
                    try await transport.send(.request(request))
                } catch {
                    failPending(id: id, error: error)
                }
            }
        }
    }

    private func receiveLoop() async {
        do {
            while !Task.isCancelled {
                guard let message = try await transport.receive() else {
                    break
                }

                switch message {
                case .response(let response):
                    guard let responseID = response.id else { continue }
                    timeoutTasks[responseID]?.cancel()
                    timeoutTasks[responseID] = nil
                    pendingMethods[responseID] = nil
                    if let continuation = pending.removeValue(forKey: responseID) {
                        if let rpcError = response.error {
                            continuation.resume(throwing: ACPClientServiceError.rpcError(code: rpcError.code.value, message: rpcError.message))
                        } else {
                            continuation.resume(returning: response)
                        }
                    }
                case .notification(let notification):
                    await onNotification?(notification)
                case .request(let request):
                    try await handleIncomingRequest(request)
                }
            }
        } catch {
            let normalized = normalizeTerminalError(error)
            let continuations = pending
            pending.removeAll()
            let timeoutTasks = timeoutTasks
            self.timeoutTasks.removeAll()
            pendingMethods.removeAll()
            timeoutTasks.values.forEach { $0.cancel() }
            continuations.values.forEach { $0.resume(throwing: normalized) }
        }
    }

    private func failPending(id: JSONRPC.ID, error: Error) {
        timeoutTasks[id]?.cancel()
        timeoutTasks[id] = nil
        pendingMethods[id] = nil
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: normalizeTerminalError(error))
    }

    private func timeoutPending(id: JSONRPC.ID, method: String) {
        guard pending[id] != nil else { return }
        failPending(id: id, error: ACPClientServiceError.requestTimeout(method: method))
    }

    private func handleIncomingRequest(_ request: JSONRPC.Request) async throws {
        guard let requestID = request.id else {
            return
        }
        switch request.method {
        case ACPMethods.sessionRequestPermission:
            try await handleTypedIncomingRequest(
                request,
                handler: onPermissionRequest,
                decodeAs: ACPSessionPermissionRequestParams.self
            )
        case ACPMethods.fsReadTextFile:
            try await handleTypedIncomingRequest(
                request,
                handler: onReadTextFile,
                decodeAs: ACPReadTextFileParams.self
            )
        case ACPMethods.fsWriteTextFile:
            try await handleTypedIncomingRequest(
                request,
                handler: onWriteTextFile,
                decodeAs: ACPWriteTextFileParams.self
            )
        case ACPMethods.terminalCreate:
            try await handleTypedIncomingRequest(
                request,
                handler: onTerminalCreate,
                decodeAs: ACPTerminalCreateParams.self
            )
        case ACPMethods.terminalOutput:
            try await handleTypedIncomingRequest(
                request,
                handler: onTerminalOutput,
                decodeAs: ACPTerminalRefParams.self
            )
        case ACPMethods.terminalWaitForExit:
            try await handleTypedIncomingRequest(
                request,
                handler: onTerminalWaitForExit,
                decodeAs: ACPTerminalRefParams.self
            )
        case ACPMethods.terminalKill:
            try await handleTypedIncomingRequest(
                request,
                handler: onTerminalKill,
                decodeAs: ACPTerminalRefParams.self
            )
        case ACPMethods.terminalRelease:
            try await handleTypedIncomingRequest(
                request,
                handler: onTerminalRelease,
                decodeAs: ACPTerminalRefParams.self
            )
        default:
            try await transport.send(.response(JSONRPC.Response(
                id: requestID,
                error: .init(code: JSONRPCErrorCode.methodNotFound, message: "Method not found: \(request.method)")
            )))
        }
    }

    private func handleTypedIncomingRequest<Params: Decodable, Result: Encodable>(
        _ request: JSONRPC.Request,
        handler: (@Sendable (Params) async throws -> Result)?,
        decodeAs: Params.Type
    ) async throws {
        guard let requestID = request.id else {
            return
        }
        guard let handler else {
            try await transport.send(.response(JSONRPC.Response(
                id: requestID,
                error: .init(code: JSONRPCErrorCode.methodNotFound, message: "Method not found: \(request.method)")
            )))
            return
        }

        do {
            let params = try ACPCodec.decodeParams(request.params, as: decodeAs)
            let result = try await handler(params)
            let payload = try ACPCodec.encodeParams(result)
            try await transport.send(.response(JSONRPC.Response(id: requestID, result: payload)))
        } catch {
            let rpcError = mapIncomingRequestError(error)
            try await transport.send(.response(JSONRPC.Response(id: requestID, error: rpcError)))
        }
    }

    private func mapIncomingRequestError(_ error: Error) -> JSONRPC.ErrorObject {
        if let nsError = error as NSError?, nsError.domain == "ACPCodec" || error is DecodingError {
            return .init(code: JSONRPCErrorCode.invalidParams, message: error.localizedDescription)
        }
        return .init(code: JSONRPCErrorCode.internalError, message: error.localizedDescription)
    }

    private func normalizeTerminalError(_ error: Error) -> Error {
        if error is CancellationError {
            return ACPTransportError.eof
        }
        return error
    }

    func _testingPendingCount() -> Int {
        pending.count
    }

    func _testingTimeoutTaskCount() -> Int {
        timeoutTasks.count
    }
}
