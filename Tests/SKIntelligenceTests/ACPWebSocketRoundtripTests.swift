import XCTest
 import STJSON
@testable import SKIACP
@testable import SKIACPAgent
@testable import SKIACPClient
@testable import SKIACPTransport
@testable import SKIntelligence

final class ACPWebSocketRoundtripTests: XCTestCase {
    func testWebSocketServerClientPromptRoundtrip() async throws {
        let (serverTransport, port) = try await ACPWebSocketTestHarness.makeServerTransport()
        let updates = WSUpdateBox()

        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoWSClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { notification in
                try? await serverTransport.send(.notification(notification))
            }
        )

        let serverLoop = Task {
            while let message = try await serverTransport.receive() {
                switch message {
                case .request(let request):
                    let response = await service.handle(request)
                    try await serverTransport.send(.response(response))
                case .notification(let notification):
                    await service.handleCancel(notification)
                case .response:
                    continue
                }
            }
        }

        let endpoint = URL(string: "ws://127.0.0.1:\(port)")!
        let clientTransport = WebSocketClientTransport(endpoint: endpoint)
        let client = ACPClientService(transport: clientTransport)
        await client.setNotificationHandler { n in
            guard n.method == ACPMethods.sessionUpdate,
                  let params = try? ACPCodec.decodeParams(n.params, as: ACPSessionUpdateParams.self) else {
                return
            }
            if let text = params.update.content?.text, !text.isEmpty {
                await updates.append(text)
            }
            await updates.appendKind(params.update.sessionUpdate)
        }

        try await client.connect()
        defer {
            serverLoop.cancel()
            Task {
                await client.close()
                await serverTransport.close()
            }
        }

        _ = try await client.initialize(.init(protocolVersion: 1, clientCapabilities: .init(), clientInfo: .init(name: "client", version: "1.0.0")))
        let session = try await client.newSession(.init(cwd: "/tmp"))
        let promptResult = try await client.prompt(.init(sessionId: session.sessionId, prompt: [.text("hello ws")]))

        XCTAssertEqual(promptResult.stopReason, .endTurn)
        let values = await updates.snapshot()
        XCTAssertEqual(values, ["ws: hello ws"])
        let kinds = await updates.snapshotKinds()
        XCTAssertGreaterThanOrEqual(kinds.count, 5)
        XCTAssertEqual(kinds[0], .availableCommandsUpdate)
        XCTAssertEqual(kinds[1], .plan)
        XCTAssertEqual(kinds[2], .toolCall)
        XCTAssertEqual(kinds[3], .toolCallUpdate)
        XCTAssertEqual(kinds[4], .agentMessageChunk)
    }

}

private actor WSUpdateBox {
    private var values: [String] = []
    private var kinds: [ACPSessionUpdateKind] = []
    func append(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
    func appendKind(_ kind: ACPSessionUpdateKind) { kinds.append(kind) }
    func snapshotKinds() -> [ACPSessionUpdateKind] { kinds }
}

private struct EchoWSClient: SKILanguageModelClient {
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
                "content": "ws: \(text)",
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
