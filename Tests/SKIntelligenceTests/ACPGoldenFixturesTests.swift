import Foundation
 import STJSON
import XCTest
@testable import SKIACP

final class ACPGoldenFixturesTests: XCTestCase {
    func testSessionUpdateGoldenFixturesRoundTrip() throws {
        let fixtureNames = [
            "agent_message_chunk_resource_link",
            "available_commands_update",
            "current_mode_update",
            "execution_state_update",
            "retry_update",
            "session_info_update",
            "tool_call_update_full",
        ]
        for name in fixtureNames {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
                XCTFail("Fixture not found: \(name).json")
                continue
            }
            let data = try Data(contentsOf: url)
            let original = try JSONDecoder().decode(AnyCodable.self, from: data)
            let decoded = try ACPCodec.decodeParams(original, as: ACPSessionUpdateParams.self)
            let reencoded = try ACPCodec.encodeParams(decoded)
            XCTAssertEqual(
                reencoded,
                original,
                "Fixture round-trip mismatch: \(url.lastPathComponent)"
            )
        }
    }
}
