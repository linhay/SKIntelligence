import XCTest
@testable import SKIACP
@testable import SKIACPTransport

final class ACPWebSocketTestHarnessTests: XCTestCase {
    func testMakeServerTransportRetriesWhenPreferredPortIsOccupied() async throws {
        let (server1, occupiedPort) = try await ACPWebSocketTestHarness.makeServerTransport()
        defer {
            Task { await server1.close() }
        }

        let (server2, retryPort) = try await ACPWebSocketTestHarness.makeServerTransport(
            preferredPort: occupiedPort,
            attempts: 20
        )
        defer {
            Task { await server2.close() }
        }

        XCTAssertNotEqual(occupiedPort, retryPort)
    }

    func testServerSendWithoutConnectedClientReturnsNotConnected() async throws {
        let (server, _) = try await ACPWebSocketTestHarness.makeServerTransport()
        defer {
            Task { await server.close() }
        }

        do {
            try await server.send(.notification(.init(method: ACPMethods.sessionUpdate, params: nil)))
            XCTFail("Expected notConnected")
        } catch let error as ACPTransportError {
            guard case .notConnected = error else {
                return XCTFail("Expected notConnected, got \(error)")
            }
        }
    }
}
