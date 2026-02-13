import XCTest
@testable import SKIACPTransport
@testable import SKIJSONRPC

final class ACPWebSocketReconnectTests: XCTestCase {
    func testClientReconnectsAfterServerRestart() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_WS_RECONNECT_TESTS"] == "1" else {
            throw XCTSkip("Live websocket reconnect test is opt-in. Set RUN_LIVE_WS_RECONNECT_TESTS=1 to enable.")
        }
        try await withTimeout(seconds: 5.0) {
            let (server1, port) = try await ACPWebSocketTestHarness.makeServerTransport()
            let endpoint = URL(string: "ws://127.0.0.1:\(port)")!
            let serverLoop1 = Task {
                try await runEchoLoop(on: server1)
            }

            let client = WebSocketClientTransport(
                endpoint: endpoint,
                options: .init(
                    heartbeatIntervalNanoseconds: 80_000_000,
                    retryPolicy: .init(maxAttempts: 6, baseDelayNanoseconds: 80_000_000),
                    maxInFlightSends: 8
                )
            )
            try await client.connect()

            let req1 = JSONRPCRequest(id: .int(1), method: "ping", params: .object(["k": .string("v1")]))
            try await withTimeout(seconds: 1.0) { try await client.send(.request(req1)) }
            let msg1 = try await withTimeout(seconds: 1.0) { try await client.receive() }
            XCTAssertEqual(msg1, .response(JSONRPCResponse(id: .int(1), result: .object(["ok": .bool(true)]))))

            await server1.close()
            serverLoop1.cancel()

            try await Task.sleep(nanoseconds: 120_000_000)

            let server2 = try await ACPWebSocketTestHarness.makeServerTransport(onFixedPort: port)
            let serverLoop2 = Task {
                try await runEchoLoop(on: server2)
            }
            defer {
                Task {
                    await client.close()
                    await server2.close()
                }
                serverLoop2.cancel()
            }

            // Leave one heartbeat window for client-side reconnect path.
            try await Task.sleep(nanoseconds: 350_000_000)

            let req2 = JSONRPCRequest(id: .int(2), method: "ping", params: .object(["k": .string("v2")]))
            try await withTimeout(seconds: 1.0) { try await client.send(.request(req2)) }
            let msg2 = try await withTimeout(seconds: 1.0) { try await client.receive() }
            XCTAssertEqual(msg2, .response(JSONRPCResponse(id: .int(2), result: .object(["ok": .bool(true)]))))
        }
    }
}

private func runEchoLoop(on server: WebSocketServerTransport) async throws {
    while let incoming = try await server.receive() {
        guard case .request(let req) = incoming else { continue }
        let resp = JSONRPCResponse(id: req.id, result: .object(["ok": .bool(true)]))
        try await server.send(.response(resp))
    }
}

private func withTimeout<T>(
    seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let nanos = UInt64(seconds * 1_000_000_000)
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: nanos)
            throw NSError(domain: "ACPWebSocketReconnectTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "timeout"])
        }
        guard let first = try await group.next() else {
            throw NSError(domain: "ACPWebSocketReconnectTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "empty"])
        }
        group.cancelAll()
        return first
    }
}
