import XCTest
@testable import SKIACP
@testable import SKIJSONRPC

final class ACPTransportBaselineTests: XCTestCase {
    func testJSONRPCEncodeDecodeBaseline() throws {
        let samples = 2_000
        let message = JSONRPCMessage.request(
            .init(
                id: .int(1),
                method: ACPMethods.sessionPrompt,
                params: try ACPCodec.encodeParams(
                    ACPSessionPromptParams(
                        sessionId: "sess_perf",
                        prompt: [.text("performance baseline")]
                    )
                )
            )
        )

        measure {
            for _ in 0..<samples {
                let data = try! JSONRPCCodec.encode(message)
                _ = try! JSONRPCCodec.decode(data)
            }
        }
    }
}
