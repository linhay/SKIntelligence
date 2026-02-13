import XCTest
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
}
