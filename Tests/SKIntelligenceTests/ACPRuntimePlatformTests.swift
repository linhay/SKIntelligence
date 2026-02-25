import XCTest
@testable import SKIACP
@testable import SKIACPClient
@testable import SKIACPTransport

final class ACPRuntimePlatformTests: XCTestCase {
    func testTerminalRuntimePlatformSemantics() async throws {
        let runtime = ACPProcessTerminalRuntime()
        let sessionID = "session-platform-test"

#if os(iOS) || os(tvOS) || os(watchOS)
        XCTAssertFalse(ACPProcessTerminalRuntime.isRuntimeSupported)
        do {
            _ = try await runtime.create(.init(sessionId: sessionID, command: "/usr/bin/env", args: ["echo", "hi"]))
            XCTFail("Expected unsupported error on this platform")
        } catch let error as ACPTransportError {
            guard case .unsupported = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
#else
        XCTAssertTrue(ACPProcessTerminalRuntime.isRuntimeSupported)
        let created = try await runtime.create(.init(sessionId: sessionID, command: "/usr/bin/env", args: ["echo", "hi"]))
        _ = try await runtime.waitForExit(.init(sessionId: sessionID, terminalId: created.terminalId))
        _ = try await runtime.release(.init(sessionId: sessionID, terminalId: created.terminalId))
#endif
    }
}
