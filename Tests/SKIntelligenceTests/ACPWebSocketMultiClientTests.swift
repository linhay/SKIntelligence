import XCTest
@testable import SKIACP
@testable import SKIACPAgent
@testable import SKIACPClient
@testable import SKIACPTransport
@testable import SKIJSONRPC
@testable import SKIntelligence

final class ACPWebSocketMultiClientTests: XCTestCase {
    func testTwoClientsCanPromptConcurrentlyWithoutCrossRouting() async throws {
        let (serverTransport, port) = try await ACPWebSocketTestHarness.makeServerTransport()

        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoMultiClient()) },
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
                    Task {
                        let response = await service.handle(request)
                        try? await serverTransport.send(.response(response))
                    }
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
        let (serverTransport, port) = try await ACPWebSocketTestHarness.makeServerTransport()
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

    func testFiveClientsCanPromptConcurrentlyWithoutCrossRouting() async throws {
        let (serverTransport, port) = try await ACPWebSocketTestHarness.makeServerTransport()

        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoMultiClient()) },
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
                    Task {
                        let response = await service.handle(request)
                        try? await serverTransport.send(.response(response))
                    }
                case .notification(let notification):
                    await service.handleCancel(notification)
                case .response:
                    continue
                }
            }
        }

        let endpoint = URL(string: "ws://127.0.0.1:\(port)")!
        var clients: [ACPClientService] = []
        var updates: [WSClientUpdateBox] = []

        for index in 0..<5 {
            let client = ACPClientService(
                transport: WebSocketClientTransport(
                    endpoint: endpoint,
                    options: .init(
                        heartbeatIntervalNanoseconds: nil,
                        retryPolicy: .init(maxAttempts: 0),
                        maxInFlightSends: 16
                    )
                ),
                requestTimeoutNanoseconds: 2_000_000_000
            )
            let updateBox = WSClientUpdateBox()
            await client.setNotificationHandler { notification in
                guard notification.method == ACPMethods.sessionUpdate,
                      let params = try? ACPCodec.decodeParams(notification.params, as: ACPSessionUpdateParams.self),
                      let text = params.update.content?.text else { return }
                await updateBox.append(text)
            }
            clients.append(client)
            updates.append(updateBox)
            _ = index
        }

        for client in clients {
            try await client.connect()
        }
        defer {
            serverLoop.cancel()
            Task {
                for client in clients {
                    await client.close()
                }
                await serverTransport.close()
            }
        }

        for (index, client) in clients.enumerated() {
            _ = try await client.initialize(
                .init(
                    protocolVersion: 1,
                    clientCapabilities: .init(),
                    clientInfo: .init(name: "client-\(index)", version: "1.0.0")
                )
            )
        }

        var sessions: [ACPSessionNewResult] = []
        for (index, client) in clients.enumerated() {
            let session = try await client.newSession(.init(cwd: "/tmp/\(index)"))
            sessions.append(session)
        }

        let results: [ACPSessionPromptResult] = try await withThrowingTaskGroup(
            of: (Int, ACPSessionPromptResult).self,
            returning: [ACPSessionPromptResult].self
        ) { group in
            for index in clients.indices {
                let client = clients[index]
                let session = sessions[index]
                group.addTask {
                    let result = try await client.prompt(
                        .init(sessionId: session.sessionId, prompt: [.text("hello-\(index)")])
                    )
                    return (index, result)
                }
            }
            var collected = Array<ACPSessionPromptResult?>(repeating: nil, count: clients.count)
            while let (index, result) = try await group.next() {
                collected[index] = result
            }
            return collected.compactMap { $0 }
        }

        XCTAssertEqual(results.count, clients.count)
        for result in results {
            XCTAssertEqual(result.stopReason, .endTurn)
        }

        for index in updates.indices {
            let list = await updates[index].snapshot()
            XCTAssertTrue(list.contains("multi: hello-\(index)"))
        }
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
