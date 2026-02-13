import XCTest
@testable import SKIACP
@testable import SKIACPAgent
@testable import SKIACPClient
@testable import SKIACPTransport
@testable import SKIntelligence

final class ACPWebSocketPermissionRoundtripTests: XCTestCase {
    func testPermissionApprovedAllowsPrompt() async throws {
        let (serverTransport, port) = try await ACPWebSocketTestHarness.makeServerTransport()
        let bridge = ACPPermissionRequestBridge()
        let updates = WSUpdateBox2()

        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoPermissionClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            permissionRequester: { params in
                try await bridge.requestPermission(params) { request in
                    try await serverTransport.send(.request(request))
                }
            },
            notificationSink: { notification in
                try? await serverTransport.send(.notification(notification))
            }
        )

        let serverLoop = Task {
            while let message = try await serverTransport.receive() {
                switch message {
                case .request(let request):
                    Task {
                        let response = await service.handle(request)
                        try? await serverTransport.send(.response(response))
                    }
                case .notification(let notification):
                    await service.handleCancel(notification)
                case .response(let response):
                    _ = await bridge.handleIncomingResponse(response)
                }
            }
        }

        let endpoint = URL(string: "ws://127.0.0.1:\(port)")!
        let clientTransport = WebSocketClientTransport(endpoint: endpoint)
        let client = ACPClientService(transport: clientTransport)
        await client.setPermissionRequestHandler { _ in
            .init(outcome: .selected(.init(optionId: "allow_once")))
        }
        await client.setNotificationHandler { n in
            guard n.method == ACPMethods.sessionUpdate,
                  let params = try? ACPCodec.decodeParams(n.params, as: ACPSessionUpdateParams.self) else { return }
            if let text = params.update.content?.text, !text.isEmpty {
                await updates.append(text)
            }
        }

        try await client.connect()
        defer {
            serverLoop.cancel()
            Task {
                await bridge.failAll(ACPTransportError.eof)
                await client.close()
                await serverTransport.close()
            }
        }

        _ = try await client.initialize(.init(protocolVersion: 1))
        let session = try await client.newSession(.init(cwd: "/tmp"))
        let result = try await client.prompt(.init(sessionId: session.sessionId, prompt: [.text("hello permission")]))
        XCTAssertEqual(result.stopReason, .endTurn)
        let values = await updates.snapshot()
        XCTAssertEqual(values, ["permission: hello permission"])
    }

    func testPermissionDeniedCancelsPrompt() async throws {
        let (serverTransport, port) = try await ACPWebSocketTestHarness.makeServerTransport()
        let bridge = ACPPermissionRequestBridge()
        let updates = WSUpdateBox2()

        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoPermissionClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            permissionRequester: { params in
                try await bridge.requestPermission(params) { request in
                    try await serverTransport.send(.request(request))
                }
            },
            notificationSink: { notification in
                try? await serverTransport.send(.notification(notification))
            }
        )

        let serverLoop = Task {
            while let message = try await serverTransport.receive() {
                switch message {
                case .request(let request):
                    Task {
                        let response = await service.handle(request)
                        try? await serverTransport.send(.response(response))
                    }
                case .notification(let notification):
                    await service.handleCancel(notification)
                case .response(let response):
                    _ = await bridge.handleIncomingResponse(response)
                }
            }
        }

        let endpoint = URL(string: "ws://127.0.0.1:\(port)")!
        let clientTransport = WebSocketClientTransport(endpoint: endpoint)
        let client = ACPClientService(transport: clientTransport)
        await client.setPermissionRequestHandler { _ in
            .init(outcome: .cancelled)
        }
        await client.setNotificationHandler { n in
            guard n.method == ACPMethods.sessionUpdate,
                  let params = try? ACPCodec.decodeParams(n.params, as: ACPSessionUpdateParams.self) else { return }
            if let text = params.update.content?.text, !text.isEmpty {
                await updates.append(text)
            }
        }

        try await client.connect()
        defer {
            serverLoop.cancel()
            Task {
                await bridge.failAll(ACPTransportError.eof)
                await client.close()
                await serverTransport.close()
            }
        }

        _ = try await client.initialize(.init(protocolVersion: 1))
        let session = try await client.newSession(.init(cwd: "/tmp"))
        let result = try await client.prompt(.init(sessionId: session.sessionId, prompt: [.text("blocked")]))
        XCTAssertEqual(result.stopReason, .cancelled)
        let values = await updates.snapshot()
        XCTAssertTrue(values.isEmpty)
    }
}

private actor WSUpdateBox2 {
    private var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
}

private struct EchoPermissionClient: SKILanguageModelClient {
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
                "content": "permission: \(text)",
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
