import Foundation
import XCTest
@testable import SKIACP
@testable import SKIACPAgent
@testable import SKIACPClient
@testable import SKIACPTransport
@testable import SKIJSONRPC
@testable import SKIntelligence

final class ACPTransportConsistencyTests: XCTestCase {
    func testSessionUpdateSequenceConsistentBetweenStdioAndWebSocket() async throws {
        guard let ski = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let stdioResult = try await withTimeout(seconds: 20) {
            try await self.runPromptSequenceViaRawJSONRPC(
                transport: ProcessStdioTransport(
                    executable: ski.path,
                    arguments: ["acp", "serve", "--transport", "stdio", "--log-level", "error"]
                )
            )
        }

        let (wsServerTransport, port) = try await ACPWebSocketTestHarness.makeServerTransport()
        let wsAgent = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoConsistencyClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { notification in
                try? await wsServerTransport.send(.notification(notification))
            }
        )
        let wsServerLoop = Task {
            while let message = try await wsServerTransport.receive() {
                switch message {
                case .request(let request):
                    let response = await wsAgent.handle(request)
                    try await wsServerTransport.send(.response(response))
                case .notification(let notification):
                    await wsAgent.handleCancel(notification)
                case .response:
                    continue
                }
            }
        }
        defer {
            wsServerLoop.cancel()
            Task { await wsServerTransport.close() }
        }

        let wsResult = try await withTimeout(seconds: 20) {
            try await self.runPromptSequence(
                transport: WebSocketClientTransport(endpoint: URL(string: "ws://127.0.0.1:\(port)")!)
            )
        }

        XCTAssertEqual(stdioResult.stopReason, .endTurn)
        XCTAssertEqual(wsResult.stopReason, .endTurn)
        XCTAssertEqual(stdioResult.kinds, wsResult.kinds)
        XCTAssertEqual(
            wsResult.kinds,
            [.availableCommandsUpdate, .plan, .toolCall, .toolCallUpdate, .agentMessageChunk]
        )
    }
}

private extension ACPTransportConsistencyTests {
    actor KindBox {
        private var values: [ACPSessionUpdateKind] = []
        func append(_ kind: ACPSessionUpdateKind) { values.append(kind) }
        func snapshot() -> [ACPSessionUpdateKind] { values }
    }

    func runPromptSequence(
        transport: any ACPTransport
    ) async throws -> (kinds: [ACPSessionUpdateKind], stopReason: ACPStopReason) {
        let client = ACPClientService(
            transport: transport,
            requestTimeoutNanoseconds: 5_000_000_000
        )
        let box = KindBox()
        await client.setNotificationHandler { notification in
            guard notification.method == ACPMethods.sessionUpdate,
                  let params = try? ACPCodec.decodeParams(notification.params, as: ACPSessionUpdateParams.self) else {
                return
            }
            await box.append(params.update.sessionUpdate)
        }

        try await client.connect()
        defer {
            Task { await client.close() }
        }

        _ = try await client.initialize(.init(protocolVersion: 1))
        let session = try await client.newSession(.init(cwd: FileManager.default.currentDirectoryPath))
        let result = try await client.prompt(.init(sessionId: session.sessionId, prompt: [.text("consistency")]))
        let kinds = await box.snapshot()
        return (kinds, result.stopReason)
    }

    func runPromptSequenceViaRawJSONRPC(
        transport: any ACPTransport
    ) async throws -> (kinds: [ACPSessionUpdateKind], stopReason: ACPStopReason) {
        try await transport.connect()
        defer {
            Task { await transport.close() }
        }

        let initialize = JSONRPCRequest(
            id: .int(1),
            method: ACPMethods.initialize,
            params: try ACPCodec.encodeParams(ACPInitializeParams(protocolVersion: 1))
        )
        try await transport.send(.request(initialize))
        _ = try await receiveResponse(id: .int(1), transport: transport)

        let newSession = JSONRPCRequest(
            id: .int(2),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: FileManager.default.currentDirectoryPath))
        )
        try await transport.send(.request(newSession))
        let sessionResponse = try await receiveResponse(id: .int(2), transport: transport)
        let session = try ACPCodec.decodeResult(sessionResponse.result, as: ACPSessionNewResult.self)

        let prompt = JSONRPCRequest(
            id: .int(3),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(
                ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("consistency")])
            )
        )
        try await transport.send(.request(prompt))

        var kinds: [ACPSessionUpdateKind] = []
        var stopReason: ACPStopReason?
        while stopReason == nil {
            guard let message = try await transport.receive() else {
                throw ACPTransportError.eof
            }
            switch message {
            case .notification(let notification):
                guard notification.method == ACPMethods.sessionUpdate else { continue }
                let params = try ACPCodec.decodeParams(notification.params, as: ACPSessionUpdateParams.self)
                kinds.append(params.update.sessionUpdate)
            case .response(let response):
                guard response.id == .int(3) else { continue }
                let result = try ACPCodec.decodeResult(response.result, as: ACPSessionPromptResult.self)
                stopReason = result.stopReason
            case .request:
                continue
            }
        }
        return (kinds, stopReason ?? .cancelled)
    }

    func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw ACPTestTimeoutError.exceeded
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func receiveResponse(
        id: JSONRPCID,
        transport: any ACPTransport
    ) async throws -> JSONRPCResponse {
        while true {
            guard let message = try await transport.receive() else {
                throw ACPTransportError.eof
            }
            switch message {
            case .response(let response) where response.id == id:
                return response
            default:
                continue
            }
        }
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

private enum ACPTestTimeoutError: Error {
    case exceeded
}

private struct EchoConsistencyClient: SKILanguageModelClient {
    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        let text = body.messages.compactMap { message -> String? in
            if case .user(let content, _) = message, case .text(let value) = content { return value }
            return nil
        }.joined(separator: "\n")

        let payload = """
        {
          "choices": [
            {
              "finish_reason": "stop",
              "message": {
                "content": "consistency: \(text)",
                "role": "assistant"
              }
            }
          ],
          "created": 0,
          "model": "test"
        }
        """

        return try SKIResponse<ChatResponseBody>(
            httpResponse: .init(status: .ok),
            data: Data(payload.utf8)
        )
    }
}
