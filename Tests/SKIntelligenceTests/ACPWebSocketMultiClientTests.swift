import XCTest
@testable import SKIACP
@testable import SKIACPAgent
@testable import SKIACPClient
@testable import SKIACPTransport
@testable import SKIJSONRPC
@testable import SKIntelligence

final class ACPWebSocketMultiClientTests: XCTestCase {
    func testTwoClientsCanPromptConcurrentlyWithoutCrossRouting() async throws {
        let port = UInt16(Int.random(in: 33000...43000))
        let serverTransport = WebSocketServerTransport(listenAddress: "127.0.0.1:\(port)")

        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoMultiClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { notification in
                try? await serverTransport.send(.notification(notification))
            }
        )

        try await serverTransport.connect()
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
        let clientA = ACPClientService(
            transport: WebSocketClientTransport(
                endpoint: endpoint,
                options: .init(
                    heartbeatIntervalNanoseconds: nil,
                    retryPolicy: .init(maxAttempts: 0),
                    maxInFlightSends: 8
                )
            ),
            requestTimeoutNanoseconds: 1_500_000_000
        )
        let clientB = ACPClientService(
            transport: WebSocketClientTransport(
                endpoint: endpoint,
                options: .init(
                    heartbeatIntervalNanoseconds: nil,
                    retryPolicy: .init(maxAttempts: 0),
                    maxInFlightSends: 8
                )
            ),
            requestTimeoutNanoseconds: 1_500_000_000
        )

        let updatesA = WSClientUpdateBox()
        let updatesB = WSClientUpdateBox()
        await clientA.setNotificationHandler { notification in
            guard notification.method == ACPMethods.sessionUpdate,
                  let params = try? ACPCodec.decodeParams(notification.params, as: ACPSessionUpdateParams.self),
                  let text = params.update.content?.text else { return }
            await updatesA.append(text)
        }
        await clientB.setNotificationHandler { notification in
            guard notification.method == ACPMethods.sessionUpdate,
                  let params = try? ACPCodec.decodeParams(notification.params, as: ACPSessionUpdateParams.self),
                  let text = params.update.content?.text else { return }
            await updatesB.append(text)
        }

        try await clientA.connect()
        try await clientB.connect()
        defer {
            serverLoop.cancel()
            Task {
                await clientA.close()
                await clientB.close()
                await serverTransport.close()
            }
        }

        _ = try await clientA.initialize(.init(protocolVersion: 1, clientCapabilities: .init(), clientInfo: .init(name: "client-a", version: "1.0.0")))
        _ = try await clientB.initialize(.init(protocolVersion: 1, clientCapabilities: .init(), clientInfo: .init(name: "client-b", version: "1.0.0")))

        let sessionA = try await clientA.newSession(.init(cwd: "/tmp/a"))
        let sessionB = try await clientB.newSession(.init(cwd: "/tmp/b"))

        async let resultA = clientA.prompt(.init(sessionId: sessionA.sessionId, prompt: [.text("hello-a")]))
        async let resultB = clientB.prompt(.init(sessionId: sessionB.sessionId, prompt: [.text("hello-b")]))
        let (promptA, promptB) = try await (resultA, resultB)

        XCTAssertEqual(promptA.stopReason, .endTurn)
        XCTAssertEqual(promptB.stopReason, .endTurn)

        let listA = await updatesA.snapshot()
        let listB = await updatesB.snapshot()
        XCTAssertTrue(listA.contains("multi: hello-a"))
        XCTAssertTrue(listB.contains("multi: hello-b"))
    }

    func testServerNotificationBroadcastsToAllConnectedClients() async throws {
        let port = UInt16(Int.random(in: 43001...52000))
        let serverTransport = WebSocketServerTransport(listenAddress: "127.0.0.1:\(port)")
        try await serverTransport.connect()
        defer {
            Task { await serverTransport.close() }
        }

        let endpoint = URL(string: "ws://127.0.0.1:\(port)")!
        let clientTransportA = WebSocketClientTransport(
            endpoint: endpoint,
            options: .init(
                heartbeatIntervalNanoseconds: nil,
                retryPolicy: .init(maxAttempts: 0),
                maxInFlightSends: 8
            )
        )
        let clientTransportB = WebSocketClientTransport(
            endpoint: endpoint,
            options: .init(
                heartbeatIntervalNanoseconds: nil,
                retryPolicy: .init(maxAttempts: 0),
                maxInFlightSends: 8
            )
        )
        try await clientTransportA.connect()
        try await clientTransportB.connect()
        try await Task.sleep(nanoseconds: 150_000_000)
        defer {
            Task {
                await clientTransportA.close()
                await clientTransportB.close()
            }
        }

        let notification = JSONRPCNotification(method: ACPMethods.sessionUpdate, params: nil)
        try await serverTransport.send(.notification(notification))

        let incomingA = try await clientTransportA.receive()
        let incomingB = try await clientTransportB.receive()

        guard case .notification(let nA) = incomingA else {
            XCTFail("client A should receive notification")
            return
        }
        guard case .notification(let nB) = incomingB else {
            XCTFail("client B should receive notification")
            return
        }
        XCTAssertEqual(nA.method, ACPMethods.sessionUpdate)
        XCTAssertEqual(nB.method, ACPMethods.sessionUpdate)
    }
}

private actor WSClientUpdateBox {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] {
        values
    }
}

private struct EchoMultiClient: SKILanguageModelClient {
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
                "content": "multi: \(text)",
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
