import XCTest
@testable import SKIACPTransport
@testable import SKIJSONRPC

final class ACPTransportPlatformTests: XCTestCase {
    func testProcessStdioTransportPlatformSemantics() async throws {
        let transport = ProcessStdioTransport(executable: "/usr/bin/env", arguments: ["cat"])

#if os(iOS) || os(tvOS) || os(watchOS)
        do {
            try await transport.connect()
            XCTFail("Expected unsupported error on this platform")
        } catch let error as ACPTransportError {
            guard case .unsupported = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
#else
        try await transport.connect()
        await transport.close()
#endif
    }
}
