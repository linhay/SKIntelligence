import XCTest
 import STJSON
@testable import SKIACP
@testable import SKIACPTransport

final class ACPWebSocketClientDeterministicReconnectTests: XCTestCase {
    func testSendRetriesWithReconnectUsingInjectedFactory() async throws {
        let endpoint = URL(string: "ws://unit.test/reconnect")!
        let request = JSONRPC.Request(id: .int(1), method: "ping", params: AnyCodable([String: AnyCodable]()))
        let message = try XCTUnwrap(String(data: JSONRPCCodec.encode(.request(request)), encoding: .utf8))

        let factory = ScriptedWebSocketFactory(
            plans: [
                .init(sendFailures: [ACPTransportError.eof], receiveQueue: []),
                .init(sendFailures: [], receiveQueue: [.string(message)])
            ]
        )
        let client = WebSocketClientTransport(
            endpoint: endpoint,
            headers: [:],
            options: .init(
                heartbeatIntervalNanoseconds: nil,
                retryPolicy: .init(maxAttempts: 2, baseDelayNanoseconds: 1_000_000),
                maxInFlightSends: 4
            ),
            connectionFactory: factory
        )

        try await client.connect()
        try await client.send(.request(request))
        let echoed = try await client.receive()
        XCTAssertEqual(echoed, .request(request))
        await client.close()
    }

    func testReceiveRetriesWithReconnectUsingInjectedFactory() async throws {
        let endpoint = URL(string: "ws://unit.test/reconnect-receive")!
        let response = JSONRPC.Response(id: .int(42), result: AnyCodable(["ok": AnyCodable(true)]))
        let payload = try JSONRPCCodec.encode(.response(response))

        let factory = ScriptedWebSocketFactory(
            plans: [
                .init(sendFailures: [], receiveQueue: []),
                .init(sendFailures: [], receiveQueue: [.data(payload)])
            ]
        )
        let client = WebSocketClientTransport(
            endpoint: endpoint,
            headers: [:],
            options: .init(
                heartbeatIntervalNanoseconds: nil,
                retryPolicy: .init(maxAttempts: 2, baseDelayNanoseconds: 1_000_000),
                maxInFlightSends: 4
            ),
            connectionFactory: factory
        )

        try await client.connect()
        let received = try await client.receive()
        guard case .response(let actual)? = received else {
            return XCTFail("Expected response, got \(String(describing: received))")
        }
        XCTAssertEqual(actual.id, .int(42))
        let resultObject = try XCTUnwrap(actual.result?.decode(to: [String: AnyCodable].self))
        XCTAssertEqual(resultObject["ok"]?.value as? Bool, true)
        XCTAssertNil(actual.error)
        await client.close()
    }
}

private final class ScriptedWebSocketFactory: WebSocketConnectionFactory {
    struct Plan {
        var sendFailures: [Error]
        var receiveQueue: [WebSocketIncomingMessage]
    }

    private let store: Store

    init(plans: [Plan]) {
        self.store = Store(plans: plans)
    }

    func make(endpoint: URL, headers: [String: String]) async throws -> any WebSocketConnection {
        let plan = await store.popNextPlan()
        return ScriptedWebSocketConnection(plan: plan)
    }

    private actor Store {
        private var plans: [Plan]

        init(plans: [Plan]) {
            self.plans = plans
        }

        func popNextPlan() -> Plan {
            if plans.isEmpty {
                return .init(sendFailures: [], receiveQueue: [])
            }
            return plans.removeFirst()
        }
    }
}

private actor ScriptedWebSocketConnection: WebSocketConnection {
    private var sendFailures: [Error]
    private var receiveQueue: [WebSocketIncomingMessage]

    init(plan: ScriptedWebSocketFactory.Plan) {
        self.sendFailures = plan.sendFailures
        self.receiveQueue = plan.receiveQueue
    }

    func send(text: String) async throws {
        if !sendFailures.isEmpty {
            throw sendFailures.removeFirst()
        }
    }

    func receive() async throws -> WebSocketIncomingMessage {
        if !receiveQueue.isEmpty {
            return receiveQueue.removeFirst()
        }
        throw ACPTransportError.eof
    }

    func sendPing() async throws {}
    func close() async {}
}
