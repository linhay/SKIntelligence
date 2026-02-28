import Foundation
import XCTest

@testable import SKIClients
@testable import SKIntelligence

final class OpenAIClientDecodingDiagnosticsTests: XCTestCase {
    func testEnrichedDecodingErrorContainsContext() throws {
        let data = Data(
            """
            {
              "choices": [],
              "created": "bad-int",
              "model": "compat-test"
            }
            """.utf8
        )

        let original = try extractDecodingError(from: data)
        let enriched = OpenAIClient.enrichDecodingError(
            original,
            data: data,
            model: "deepseek-chat",
            url: URL(string: "https://api.example.com/v1/chat/completions")!
        )

        let context = decodingContext(from: enriched)
        XCTAssertTrue(context.codingPath.map(\.stringValue).contains("created"))
        XCTAssertTrue(context.debugDescription.contains("model=deepseek-chat"))
        XCTAssertTrue(context.debugDescription.contains("url=https://api.example.com/v1/chat/completions"))
        XCTAssertTrue(context.debugDescription.contains("responseSnippet="))
    }

    func testEnrichedDecodingErrorRedactsSensitiveFieldsInSnippet() throws {
        let data = Data(
            """
            {
              "choices": [],
              "created": "bad-int",
              "model": "compat-test",
              "api_key": "secret-key",
              "authorization": "Bearer 12345"
            }
            """.utf8
        )

        let original = try extractDecodingError(from: data)
        let enriched = OpenAIClient.enrichDecodingError(
            original,
            data: data,
            model: "dashscope",
            url: URL(string: "https://dashscope.example.com/compatible-mode/v1/chat/completions")!
        )

        let description = decodingContext(from: enriched).debugDescription
        XCTAssertFalse(description.contains("secret-key"))
        XCTAssertFalse(description.contains("Bearer 12345"))
        XCTAssertTrue(description.contains("\"api_key\": \"***\""))
        XCTAssertTrue(description.contains("\"authorization\": \"***\""))
    }

    private func extractDecodingError(from data: Data) throws -> DecodingError {
        do {
            _ = try JSONDecoder().decode(ChatResponseBody.self, from: data)
            XCTFail("Expected decoding to fail")
            throw NSError(domain: "Test", code: -1)
        } catch let error as DecodingError {
            return error
        }
    }

    private func decodingContext(from error: DecodingError) -> DecodingError.Context {
        switch error {
        case .typeMismatch(_, let context):
            return context
        case .valueNotFound(_, let context):
            return context
        case .keyNotFound(_, let context):
            return context
        case .dataCorrupted(let context):
            return context
        @unknown default:
            XCTFail("Unknown DecodingError case")
            return .init(codingPath: [], debugDescription: "unknown")
        }
    }
}
