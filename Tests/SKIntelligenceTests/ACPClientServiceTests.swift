import XCTest
 import STJSON
@testable import SKIACP
@testable import SKIACPClient
@testable import SKIACPTransport

actor ScriptedTransport: ACPTransport {
    private(set) var sent: [JSONRPCMessage] = []
    private var inbox: [JSONRPCMessage] = []
    private var connected = false

    func connect() async throws {
        connected = true
    }

    func send(_ message: JSONRPCMessage) async throws {
        guard connected else { throw ACPTransportError.notConnected }
        sent.append(message)

        if case .request(let request) = message {
            switch request.method {
            case ACPMethods.initialize:
                let result = ACPInitializeResult(protocolVersion: 1, agentCapabilities: .init(loadSession: true), agentInfo: .init(name: "mock-agent", version: "1.0.0"))
                let value = try ACPCodec.encodeParams(result)
                inbox.append(.response(JSONRPC.Response(id: request.id!, result: value)))
            case ACPMethods.sessionNew:
                let result = ACPSessionNewResult(sessionId: "sess_test")
                let value = try ACPCodec.encodeParams(result)
                inbox.append(.response(JSONRPC.Response(id: request.id!, result: value)))
            case ACPMethods.sessionPrompt:
                let update = ACPSessionUpdateParams(
                    sessionId: "sess_test",
                    update: .init(sessionUpdate: .agentMessageChunk, content: .init(type: "text", text: "hello from agent"))
                )
                inbox.append(.notification(.init(method: ACPMethods.sessionUpdate, params: try ACPCodec.encodeParams(update))))
                let result = ACPSessionPromptResult(stopReason: .endTurn)
                inbox.append(.response(JSONRPC.Response(id: request.id!, result: try ACPCodec.encodeParams(result))))
            default:
                inbox.append(.response(JSONRPC.Response(id: request.id!, error: .init(code: -32601, message: "method not found"))))
            }
        }
    }

    func receive() async throws -> JSONRPCMessage? {
        guard connected else { throw ACPTransportError.notConnected }
        while inbox.isEmpty {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return inbox.removeFirst()
    }

    func close() async {
        connected = false
    }
}

actor SilentTransport: ACPTransport {
    private var connected = false

    func connect() async throws { connected = true }
    func send(_ message: JSONRPCMessage) async throws {
        guard connected else { throw ACPTransportError.notConnected }
        _ = message
    }
    func receive() async throws -> JSONRPCMessage? {
        guard connected else { throw ACPTransportError.notConnected }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return nil
    }
    func close() async { connected = false }
}

actor DuplicateResponseTransport: ACPTransport {
    private var inbox: [JSONRPCMessage] = []
    private var connected = false

    func connect() async throws { connected = true }

    func send(_ message: JSONRPCMessage) async throws {
        guard connected else { throw ACPTransportError.notConnected }
        guard case .request(let request) = message else { return }

        switch request.method {
        case ACPMethods.initialize:
            let first = ACPInitializeResult(protocolVersion: 1, agentCapabilities: .init(loadSession: true), agentInfo: .init(name: "a", version: "1"))
            let second = ACPInitializeResult(protocolVersion: 9, agentCapabilities: .init(loadSession: false), agentInfo: .init(name: "b", version: "9"))
            inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(first))))
            inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(second))))
            inbox.append(.response(.init(id: .int(99999), result: AnyCodable(["ignored": AnyCodable(true)]))))
        case ACPMethods.sessionNew:
            let result = ACPSessionNewResult(sessionId: "sess_ok")
            inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(result))))
        default:
            inbox.append(.response(.init(id: request.id!, error: .init(code: -32601, message: "unsupported"))))
        }
    }

    func receive() async throws -> JSONRPCMessage? {
        guard connected else { throw ACPTransportError.notConnected }
        while inbox.isEmpty {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return inbox.removeFirst()
    }

    func close() async { connected = false }
}

actor ChaoticResponseTransport: ACPTransport {
    private var inbox: [JSONRPCMessage] = []
    private var connected = false

    func connect() async throws { connected = true }

    func send(_ message: JSONRPCMessage) async throws {
        guard connected else { throw ACPTransportError.notConnected }
        guard case .request(let request) = message else { return }

        let requestID = request.id!
        Task {
            // Emit an unknown response first to verify client ignores it.
            self.enqueue(.response(.init(id: .int(777777), result: AnyCodable(["noise": AnyCodable(true)]))))

            // Stable pseudo-random delay derived from request id.
            let delay = UInt64((Self.idInt(requestID) % 7 + 1) * 2_000_000)
            try? await Task.sleep(nanoseconds: delay)

            switch request.method {
            case ACPMethods.sessionNew:
                let suffix = Self.idInt(requestID)
                let result = ACPSessionNewResult(sessionId: "sess_\(suffix)")
                self.enqueue(.response(.init(id: requestID, result: try! ACPCodec.encodeParams(result))))
            case ACPMethods.initialize:
                let result = ACPInitializeResult(protocolVersion: 1, agentCapabilities: .init(loadSession: true), agentInfo: .init(name: "chaos", version: "1"))
                self.enqueue(.response(.init(id: requestID, result: try! ACPCodec.encodeParams(result))))
            default:
                self.enqueue(.response(.init(id: requestID, error: .init(code: -32601, message: "unsupported"))))
            }
        }
    }

    func receive() async throws -> JSONRPCMessage? {
        guard connected else { throw ACPTransportError.notConnected }
        while inbox.isEmpty {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return inbox.removeFirst()
    }

    func close() async { connected = false }

    private func enqueue(_ message: JSONRPCMessage) {
        inbox.append(message)
    }

    private static func idInt(_ id: JSONRPC.ID) -> Int {
        switch id {
        case .int(let value): return value
        case .string(let value): return abs(value.hashValue)
        case .null: return 0
        }
    }
}

actor HangingTransport: ACPTransport {
    private var connected = false

    func connect() async throws { connected = true }

    func send(_ message: JSONRPCMessage) async throws {
        guard connected else { throw ACPTransportError.notConnected }
        _ = message
    }

    func receive() async throws -> JSONRPCMessage? {
        guard connected else { throw ACPTransportError.notConnected }
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return nil
    }

    func close() async { connected = false }
}

actor IDCaptureTransport: ACPTransport {
    private var connected = false
    private var inbox: [JSONRPCMessage] = []
    private(set) var requestIDs: [Int] = []

    func connect() async throws { connected = true }

    func send(_ message: JSONRPCMessage) async throws {
        guard connected else { throw ACPTransportError.notConnected }
        guard case .request(let request) = message else { return }
        let id = Self.idInt(request.id!)
        requestIDs.append(id)

        switch request.method {
        case ACPMethods.sessionNew:
            let result = ACPSessionNewResult(sessionId: "sess_\(id)")
            inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(result))))
        case ACPMethods.initialize:
            let result = ACPInitializeResult(protocolVersion: 1, agentCapabilities: .init(loadSession: true), agentInfo: .init(name: "idcap", version: "1"))
            inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(result))))
        default:
            inbox.append(.response(.init(id: request.id!, error: .init(code: -32601, message: "unsupported"))))
        }
    }

    func receive() async throws -> JSONRPCMessage? {
        guard connected else { throw ACPTransportError.notConnected }
        while inbox.isEmpty {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return inbox.removeFirst()
    }

    func close() async { connected = false }

    private static func idInt(_ id: JSONRPC.ID) -> Int {
        switch id {
        case .int(let value): return value
        case .string(let value): return abs(value.hashValue)
        case .null: return 0
        }
    }
}

actor PermissionRequestTransport: ACPTransport {
    private var connected = false
    private var inbox: [JSONRPCMessage] = []
    private(set) var permissionResponses: [JSONRPC.Response] = []

    func connect() async throws {
        connected = true
        let params = try ACPCodec.encodeParams(
            ACPSessionPermissionRequestParams(
                sessionId: "sess_perm",
                toolCall: .init(toolCallId: "call_perm", title: "Need approval"),
                options: [
                    .init(optionId: "allow_once", name: "Allow once", kind: .allowOnce),
                    .init(optionId: "reject_once", name: "Reject once", kind: .rejectOnce)
                ]
            )
        )
        inbox.append(.request(.init(id: .string("perm-1"), method: ACPMethods.sessionRequestPermission, params: params)))
    }

    func send(_ message: JSONRPCMessage) async throws {
        guard connected else { throw ACPTransportError.notConnected }
        switch message {
        case .request(let request):
            if request.method == ACPMethods.initialize {
                let result = ACPInitializeResult(protocolVersion: 1, agentCapabilities: .init(loadSession: true), agentInfo: .init(name: "perm-agent", version: "1.0.0"))
                inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(result))))
            }
        case .response(let response):
            permissionResponses.append(response)
        case .notification:
            break
        }
    }

    func receive() async throws -> JSONRPCMessage? {
        guard connected else { throw ACPTransportError.notConnected }
        while inbox.isEmpty {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return inbox.removeFirst()
    }

    func close() async {
        connected = false
    }
}

actor ClientSideMethodRequestTransport: ACPTransport {
    private var connected = false
    private var inbox: [JSONRPCMessage] = []
    private(set) var responses: [JSONRPC.Response] = []

    func connect() async throws {
        connected = true
        let fsParams = try ACPCodec.encodeParams(
            ACPReadTextFileParams(sessionId: "sess_ops", path: "/tmp/readme.md", line: 1, limit: 5)
        )
        inbox.append(.request(.init(id: .string("fs-1"), method: ACPMethods.fsReadTextFile, params: fsParams)))

        let terminalParams = try ACPCodec.encodeParams(
            ACPTerminalCreateParams(sessionId: "sess_ops", command: "echo", args: ["hi"])
        )
        inbox.append(.request(.init(id: .string("term-1"), method: ACPMethods.terminalCreate, params: terminalParams)))
    }

    func send(_ message: JSONRPCMessage) async throws {
        guard connected else { throw ACPTransportError.notConnected }
        switch message {
        case .request(let request):
            if request.method == ACPMethods.initialize {
                let result = ACPInitializeResult(
                    protocolVersion: 1,
                    agentCapabilities: .init(loadSession: true),
                    agentInfo: .init(name: "ops-agent", version: "1.0.0")
                )
                inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(result))))
            }
        case .response(let response):
            responses.append(response)
        case .notification:
            break
        }
    }

    func receive() async throws -> JSONRPCMessage? {
        guard connected else { throw ACPTransportError.notConnected }
        while inbox.isEmpty {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return inbox.removeFirst()
    }

    func close() async {
        connected = false
    }
}

actor SessionDomainTransport: ACPTransport {
    private var connected = false
    private var inbox: [JSONRPCMessage] = []
    private var currentModelBySession: [String: String] = [:]

    func connect() async throws { connected = true }

    func send(_ message: JSONRPCMessage) async throws {
        guard connected else { throw ACPTransportError.notConnected }
        guard case .request(let request) = message else { return }

        switch request.method {
        case ACPMethods.initialize:
            let result = ACPInitializeResult(protocolVersion: 1, agentCapabilities: .init(loadSession: true), agentInfo: .init(name: "domain-agent", version: "1.0.0"))
            inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(result))))
        case ACPMethods.sessionNew:
            let result = ACPSessionNewResult(
                sessionId: "sess_domain",
                models: .init(currentModelId: "default", availableModels: [.init(modelId: "default", name: "Default"), .init(modelId: "gpt-5", name: "GPT-5")])
            )
            currentModelBySession["sess_domain"] = "default"
            inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(result))))
        case ACPMethods.sessionSetModel:
            let params = try ACPCodec.decodeParams(request.params, as: ACPSessionSetModelParams.self)
            currentModelBySession[params.sessionId] = params.modelId
            inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(ACPSessionSetModelResult()))))
        case ACPMethods.sessionList:
            let result = ACPSessionListResult(sessions: [.init(sessionId: "sess_domain", cwd: "/tmp", title: "Domain Session")], nextCursor: nil)
            inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(result))))
        case ACPMethods.sessionResume:
            let result = ACPSessionResumeResult(
                modes: .init(currentModeId: "default", availableModes: [.init(id: "default", name: "Default")]),
                models: .init(currentModelId: currentModelBySession["sess_domain"] ?? "default", availableModels: [.init(modelId: "default", name: "Default"), .init(modelId: "gpt-5", name: "GPT-5")]),
                configOptions: []
            )
            inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(result))))
        case ACPMethods.sessionFork:
            let result = ACPSessionForkResult(
                sessionId: "sess_forked",
                modes: .init(currentModeId: "default", availableModes: [.init(id: "default", name: "Default")]),
                models: .init(currentModelId: currentModelBySession["sess_domain"] ?? "default", availableModels: [.init(modelId: "default", name: "Default"), .init(modelId: "gpt-5", name: "GPT-5")]),
                configOptions: []
            )
            inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(result))))
        case ACPMethods.sessionDelete:
            inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(ACPSessionDeleteResult()))))
        case ACPMethods.sessionExport:
            let result = ACPSessionExportResult(
                sessionId: "sess_domain",
                format: .jsonl,
                mimeType: "application/x-ndjson",
                content: "{\"type\":\"session\"}\n{\"message\":{\"role\":\"user\"}}\n"
            )
            inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(result))))
        case ACPMethods.logout:
            inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(ACPLogoutResult()))))
        default:
            inbox.append(.response(.init(id: request.id!, error: .init(code: -32601, message: "unsupported"))))
        }
    }

    func receive() async throws -> JSONRPCMessage? {
        guard connected else { throw ACPTransportError.notConnected }
        while inbox.isEmpty {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return inbox.removeFirst()
    }

    func close() async { connected = false }
}

final class ACPClientServiceTests: XCTestCase {
    func testStopSessionSendsRequestAndDecodesResult() async throws {
        actor StopSessionTransport: ACPTransport {
            private(set) var sent: [JSONRPCMessage] = []
            private var inbox: [JSONRPCMessage] = []
            private var connected = false

            func connect() async throws { connected = true }

            func send(_ message: JSONRPCMessage) async throws {
                guard connected else { throw ACPTransportError.notConnected }
                sent.append(message)
                guard case .request(let request) = message else { return }

                switch request.method {
                case ACPMethods.initialize:
                    let result = ACPInitializeResult(
                        protocolVersion: 1,
                        agentCapabilities: .init(loadSession: true),
                        agentInfo: .init(name: "stop-agent", version: "1.0.0")
                    )
                    inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(result))))
                case ACPMethods.sessionStop:
                    inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(ACPSessionStopResult()))))
                default:
                    inbox.append(.response(.init(id: request.id!, error: .init(code: -32601, message: "unsupported"))))
                }
            }

            func receive() async throws -> JSONRPCMessage? {
                guard connected else { throw ACPTransportError.notConnected }
                while inbox.isEmpty {
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                return inbox.removeFirst()
            }

            func close() async { connected = false }
        }

        let transport = StopSessionTransport()
        let client = ACPClientService(transport: transport)
        try await client.connect()
        defer { Task { await client.close() } }

        _ = try await client.initialize(.init(protocolVersion: 1))
        _ = try await client.stopSession(.init(sessionId: "sess_test_stop"))

        let sent = await transport.sent
        let hasStopRequest = sent.contains { message in
            guard case .request(let request) = message else { return false }
            return request.method == ACPMethods.sessionStop
        }
        XCTAssertTrue(hasStopRequest)
    }

    func testCancelRequestSendsProtocolNotification() async throws {
        let transport = ScriptedTransport()
        let client = ACPClientService(transport: transport)
        try await client.connect()
        defer { Task { await client.close() } }

        _ = try await client.initialize(.init(protocolVersion: 1))
        try await client.cancelRequest(.init(requestId: .int(7)))

        let sent = await transport.sent
        let hasCancelRequest = sent.contains { message in
            guard case .notification(let notification) = message else { return false }
            return notification.method == ACPMethods.cancelRequest
        }
        XCTAssertTrue(hasCancelRequest)
    }

    func testSessionDomainMethodsSetModelListResumeFork() async throws {
        let transport = SessionDomainTransport()
        let client = ACPClientService(transport: transport)
        try await client.connect()
        defer { Task { await client.close() } }

        _ = try await client.initialize(.init(protocolVersion: 1))
        let newSession = try await client.newSession(.init(cwd: "/tmp"))
        XCTAssertEqual(newSession.models?.currentModelId, "default")

        _ = try await client.setModel(.init(sessionId: newSession.sessionId, modelId: "gpt-5"))

        let list = try await client.listSessions(.init())
        XCTAssertEqual(list.sessions.first?.sessionId, "sess_domain")

        let resumed = try await client.resumeSession(.init(sessionId: newSession.sessionId, cwd: "/tmp"))
        XCTAssertEqual(resumed.models?.currentModelId, "gpt-5")

        let forked = try await client.forkSession(.init(sessionId: newSession.sessionId, cwd: "/tmp/fork"))
        XCTAssertEqual(forked.sessionId, "sess_forked")
        XCTAssertEqual(forked.models?.currentModelId, "gpt-5")

        let exported = try await client.exportSession(.init(sessionId: newSession.sessionId))
        XCTAssertEqual(exported.sessionId, "sess_domain")
        XCTAssertEqual(exported.format, .jsonl)
        XCTAssertTrue(exported.content.contains("\"type\":\"session\""))

        _ = try await client.deleteSession(.init(sessionId: newSession.sessionId))
        _ = try await client.logout()
    }

    func testClientSideFSAndTerminalHandlersRespondToIncomingRequests() async throws {
        let transport = ClientSideMethodRequestTransport()
        let client = ACPClientService(transport: transport)
        await client.setReadTextFileHandler { params in
            XCTAssertEqual(params.path, "/tmp/readme.md")
            return .init(content: "hello")
        }
        await client.setTerminalCreateHandler { params in
            XCTAssertEqual(params.command, "echo")
            return .init(terminalId: "term-001")
        }

        try await client.connect()
        defer { Task { await client.close() } }

        _ = try await client.initialize(.init(protocolVersion: 1))
        try await Task.sleep(nanoseconds: 50_000_000)

        let responses = await transport.responses
        XCTAssertEqual(responses.count, 2)
        XCTAssertEqual(Set(responses.map(\.id)), Set([.string("fs-1"), .string("term-1")]))

        let fsResponse = responses.first { $0.id == .string("fs-1") }
        let fsResult = try ACPCodec.decodeResult(fsResponse?.result, as: ACPReadTextFileResult.self)
        XCTAssertEqual(fsResult.content, "hello")

        let termResponse = responses.first { $0.id == .string("term-1") }
        let termResult = try ACPCodec.decodeResult(termResponse?.result, as: ACPTerminalCreateResult.self)
        XCTAssertEqual(termResult.terminalId, "term-001")
    }

    func testPermissionRequestHandlerReturnsResultResponse() async throws {
        let transport = PermissionRequestTransport()
        let client = ACPClientService(transport: transport)
        await client.setPermissionRequestHandler { params in
            XCTAssertEqual(params.sessionId, "sess_perm")
            return ACPSessionPermissionRequestResult(outcome: .selected(.init(optionId: "allow_once")))
        }

        try await client.connect()
        defer { Task { await client.close() } }

        _ = try await client.initialize(.init(protocolVersion: 1))
        try await Task.sleep(nanoseconds: 40_000_000)

        let responses = await transport.permissionResponses
        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(responses.first?.id, .string("perm-1"))
        let result = try ACPCodec.decodeResult(responses.first?.result, as: ACPSessionPermissionRequestResult.self)
        guard case .selected(let selected) = result.outcome else {
            return XCTFail("Expected selected outcome")
        }
        XCTAssertEqual(selected.optionId, "allow_once")
    }

    func testPermissionRequestWithoutHandlerReturnsMethodNotFound() async throws {
        let transport = PermissionRequestTransport()
        let client = ACPClientService(transport: transport)
        try await client.connect()
        defer { Task { await client.close() } }

        _ = try await client.initialize(.init(protocolVersion: 1))
        try await Task.sleep(nanoseconds: 40_000_000)

        let responses = await transport.permissionResponses
        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(responses.first?.id, .string("perm-1"))
        XCTAssertEqual(responses.first?.error?.code.value, JSONRPCErrorCode.methodNotFound)
    }

    func testInitializeNewPromptFlow() async throws {
        let transport = ScriptedTransport()
        let client = ACPClientService(transport: transport)
        let updates = UpdateBox()
        await client.setNotificationHandler { n in
            guard n.method == ACPMethods.sessionUpdate,
                  let params = try? ACPCodec.decodeParams(n.params, as: ACPSessionUpdateParams.self)
            else { return }
            await updates.append(params.update.content?.text ?? "")
        }

        try await client.connect()
        defer {
            Task { await client.close() }
        }

        let initResult = try await client.initialize(.init(protocolVersion: 1, clientCapabilities: .init(), clientInfo: .init(name: "client", version: "1.0.0")))
        XCTAssertEqual(initResult.protocolVersion, 1)
        XCTAssertTrue(initResult.agentCapabilities.loadSession)

        let newSession = try await client.newSession(.init(cwd: "/tmp"))
        XCTAssertEqual(newSession.sessionId, "sess_test")

        let promptResult = try await client.prompt(.init(sessionId: "sess_test", prompt: [.text("hi")]))
        XCTAssertEqual(promptResult.stopReason, .endTurn)
        let updateValues = await updates.snapshot()
        XCTAssertEqual(updateValues, ["hello from agent"])
    }

    func testRequestTimeout() async throws {
        let transport = SilentTransport()
        let client = ACPClientService(transport: transport, requestTimeoutNanoseconds: 40_000_000)
        try await client.connect()
        defer { Task { await client.close() } }

        do {
            _ = try await client.initialize(.init(protocolVersion: 1))
            XCTFail("Expected timeout")
        } catch let error as ACPClientServiceError {
            guard case .requestTimeout(let method) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(method, ACPMethods.initialize)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDuplicateAndUnknownResponsesAreIgnored() async throws {
        let transport = DuplicateResponseTransport()
        let client = ACPClientService(transport: transport)
        try await client.connect()
        defer { Task { await client.close() } }

        let initResult = try await client.initialize(.init(protocolVersion: 1))
        XCTAssertEqual(initResult.protocolVersion, 1)
        XCTAssertTrue(initResult.agentCapabilities.loadSession)

        let session = try await client.newSession(.init(cwd: "/tmp"))
        XCTAssertEqual(session.sessionId, "sess_ok")
    }

    func testConcurrentRequestsHandleOutOfOrderResponses() async throws {
        let transport = ChaoticResponseTransport()
        let client = ACPClientService(transport: transport, requestTimeoutNanoseconds: 2_000_000_000)
        try await client.connect()
        defer { Task { await client.close() } }

        _ = try await client.initialize(.init(protocolVersion: 1))

        let count = 40
        let sessionIDs = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<count {
                group.addTask {
                    let result = try await client.newSession(.init(cwd: "/tmp"))
                    return result.sessionId
                }
            }

            var values: [String] = []
            while let value = try await group.next() {
                values.append(value)
            }
            return values
        }

        XCTAssertEqual(sessionIDs.count, count)
        XCTAssertEqual(Set(sessionIDs).count, count)
        let pendingCount = await client._testingPendingCount()
        let timeoutTaskCount = await client._testingTimeoutTaskCount()
        XCTAssertEqual(pendingCount, 0)
        XCTAssertEqual(timeoutTaskCount, 0)
    }

    func testCloseCancelsInFlightRequestWithEOF() async throws {
        let transport = HangingTransport()
        let client = ACPClientService(transport: transport, requestTimeoutNanoseconds: 5_000_000_000)
        try await client.connect()

        let task = Task {
            try await client.initialize(.init(protocolVersion: 1))
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        await client.close()

        do {
            _ = try await task.value
            XCTFail("Expected EOF")
        } catch let error as ACPTransportError {
            guard case .eof = error else {
                return XCTFail("Expected EOF, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let pendingCount = await client._testingPendingCount()
        let timeoutTaskCount = await client._testingTimeoutTaskCount()
        XCTAssertEqual(pendingCount, 0)
        XCTAssertEqual(timeoutTaskCount, 0)
    }

    func testCloseCancelsMultipleInFlightRequestsWithEOF() async throws {
        let transport = HangingTransport()
        let client = ACPClientService(transport: transport, requestTimeoutNanoseconds: 5_000_000_000)
        try await client.connect()

        let tasks = (0..<6).map { _ in
            Task {
                try await client.newSession(.init(cwd: "/tmp"))
            }
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        await client.close()

        for task in tasks {
            do {
                _ = try await task.value
                XCTFail("Expected EOF")
            } catch let error as ACPTransportError {
                guard case .eof = error else {
                    return XCTFail("Expected EOF, got \(error)")
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        let pendingCount = await client._testingPendingCount()
        let timeoutTaskCount = await client._testingTimeoutTaskCount()
        XCTAssertEqual(pendingCount, 0)
        XCTAssertEqual(timeoutTaskCount, 0)
    }

    func testCloseBeforeTimeoutPrefersEOF() async throws {
        let transport = HangingTransport()
        let client = ACPClientService(transport: transport, requestTimeoutNanoseconds: 300_000_000)
        try await client.connect()

        let task = Task {
            try await client.initialize(.init(protocolVersion: 1))
        }

        try await Task.sleep(nanoseconds: 80_000_000)
        await client.close()

        do {
            _ = try await task.value
            XCTFail("Expected EOF")
        } catch let error as ACPTransportError {
            guard case .eof = error else {
                return XCTFail("Expected EOF, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTimeoutBeforeCloseReturnsRequestTimeout() async throws {
        let transport = HangingTransport()
        let client = ACPClientService(transport: transport, requestTimeoutNanoseconds: 60_000_000)
        try await client.connect()
        defer { Task { await client.close() } }

        do {
            _ = try await client.initialize(.init(protocolVersion: 1))
            XCTFail("Expected timeout")
        } catch let error as ACPClientServiceError {
            guard case .requestTimeout(let method) = error else {
                return XCTFail("Expected request timeout, got \(error)")
            }
            XCTAssertEqual(method, ACPMethods.initialize)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCloseIsIdempotent() async throws {
        let transport = ScriptedTransport()
        let client = ACPClientService(transport: transport)
        try await client.connect()

        await client.close()
        await client.close()

        let pendingCount = await client._testingPendingCount()
        let timeoutTaskCount = await client._testingTimeoutTaskCount()
        XCTAssertEqual(pendingCount, 0)
        XCTAssertEqual(timeoutTaskCount, 0)
    }

    func testCallAfterCloseReturnsNotConnected() async throws {
        let transport = ScriptedTransport()
        let client = ACPClientService(transport: transport)
        try await client.connect()
        await client.close()

        do {
            _ = try await client.initialize(.init(protocolVersion: 1))
            XCTFail("Expected notConnected")
        } catch let error as ACPTransportError {
            guard case .notConnected = error else {
                return XCTFail("Expected notConnected, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSessionUpdateDeliveredBeforePromptReturn() async throws {
        let transport = ScriptedTransport()
        let client = ACPClientService(transport: transport)
        let events = EventBox()

        await client.setNotificationHandler { n in
            guard n.method == ACPMethods.sessionUpdate else { return }
            await events.append("update")
        }

        try await client.connect()
        defer { Task { await client.close() } }

        _ = try await client.initialize(.init(protocolVersion: 1))
        let session = try await client.newSession(.init(cwd: "/tmp"))
        _ = try await client.prompt(.init(sessionId: session.sessionId, prompt: [.text("hi")]))
        await events.append("prompt_result")

        let values = await events.snapshot()
        XCTAssertEqual(values, ["update", "prompt_result"])
    }

    func testConcurrentRequestIDsAreUniqueAndContiguous() async throws {
        let transport = IDCaptureTransport()
        let client = ACPClientService(transport: transport, requestTimeoutNanoseconds: 2_000_000_000)
        try await client.connect()
        defer { Task { await client.close() } }

        let count = 200
        let ids = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<count {
                group.addTask {
                    let result = try await client.newSession(.init(cwd: "/tmp"))
                    return result.sessionId
                }
            }

            var values: [String] = []
            while let value = try await group.next() {
                values.append(value)
            }
            return values
        }

        XCTAssertEqual(ids.count, count)
        let sentIDs = await transport.requestIDs
        XCTAssertEqual(sentIDs.count, count)
        let sorted = sentIDs.sorted()
        XCTAssertEqual(sorted, Array(1...count))
    }

    func testLongRunSequentialRequestsKeepInternalStateClean() async throws {
        let transport = IDCaptureTransport()
        let client = ACPClientService(transport: transport, requestTimeoutNanoseconds: 2_000_000_000)
        try await client.connect()
        defer { Task { await client.close() } }

        _ = try await client.initialize(.init(protocolVersion: 1))
        for _ in 0..<1000 {
            _ = try await client.newSession(.init(cwd: "/tmp"))
        }

        let pendingCount = await client._testingPendingCount()
        let timeoutTaskCount = await client._testingTimeoutTaskCount()
        XCTAssertEqual(pendingCount, 0)
        XCTAssertEqual(timeoutTaskCount, 0)
    }

    func testConcurrentRequestsWithRandomCloseAreStable() async throws {
        let transport = ChaoticResponseTransport()
        let client = ACPClientService(transport: transport, requestTimeoutNanoseconds: 120_000_000)
        try await client.connect()

        let total = 200
        let closeTask = Task {
            // deterministic pseudo-random close window in [10ms, 30ms]
            let delayMs = 10 + (Int(Date().timeIntervalSince1970 * 1000) % 21)
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            await client.close()
        }

        let outcomes = await withTaskGroup(of: Result<String, Error>.self) { group in
            for _ in 0..<total {
                group.addTask {
                    do {
                        let result = try await client.newSession(.init(cwd: "/tmp"))
                        return .success(result.sessionId)
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var values: [Result<String, Error>] = []
            while let value = await group.next() {
                values.append(value)
            }
            return values
        }
        _ = await closeTask.result

        XCTAssertEqual(outcomes.count, total)
        for outcome in outcomes {
            switch outcome {
            case .success(let sessionID):
                XCTAssertTrue(sessionID.hasPrefix("sess_"))
            case .failure(let error as ACPTransportError):
                switch error {
                case .eof, .notConnected:
                    break
                default:
                    XCTFail("Unexpected ACPTransportError: \(error)")
                }
            case .failure(let error as ACPClientServiceError):
                guard case .requestTimeout(let method) = error else {
                    return XCTFail("Unexpected ACPClientServiceError: \(error)")
                }
                XCTAssertEqual(method, ACPMethods.sessionNew)
            case .failure(let error):
                XCTFail("Unexpected error: \(error)")
            }
        }

        let pendingCount = await client._testingPendingCount()
        let timeoutTaskCount = await client._testingTimeoutTaskCount()
        XCTAssertEqual(pendingCount, 0)
        XCTAssertEqual(timeoutTaskCount, 0)
    }
}

private actor UpdateBox {
    private var values: [String] = []
    func append(_ value: String) {
        values.append(value)
    }
    func snapshot() -> [String] { values }
}

private actor EventBox {
    private var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
}
