import MCP
import XCTest

@testable import SKIntelligence

final class SKIMCPClientTextExtractionTests: XCTestCase {

    func testGivenStringPayloadWhenExtractingThenReturnsText() {
        let content: MCP.Tool.Content = .text("hello")

        let text = SKIMCPClient.extractText(content)

        XCTAssertEqual(text, "hello")
    }

    func testGivenTupleLikePayloadWhenExtractingThenReturnsNamedText() {
        let payload = (text: "hello", annotations: Optional<String>.none, _meta: Optional<String>.none)

        let text = SKIMCPClient.extractTextPayload(payload)

        XCTAssertEqual(text, "hello")
    }

    func testGivenNonTextContentWhenExtractingThenReturnsNil() {
        let content: MCP.Tool.Content = .image(data: "base64", mimeType: "image/png", metadata: nil)

        let text = SKIMCPClient.extractText(content)

        XCTAssertNil(text)
    }
}
