import XCTest
import HTTPTypes
import JSONSchemaBuilder
@testable import SKIntelligence

final class SKITokenUsageTrackingTests: XCTestCase {

    func testNonStreamingAccumulatesUsage() async throws {
        let client = UsageSequenceClient(
            responses: [
                makeChatResponseJSON(content: "hello", usage: makeUsageJSON(prompt: 10, completion: 5, total: 15, reasoning: 2))
            ]
        )
        let session = SKILanguageModelSession(client: client)

        _ = try await session.respond(to: "hi")
        let snapshot = await session.tokenUsageSnapshot()

        XCTAssertEqual(snapshot.promptTokens, 10)
        XCTAssertEqual(snapshot.completionTokens, 5)
        XCTAssertEqual(snapshot.totalTokens, 15)
        XCTAssertEqual(snapshot.reasoningTokens, 2)
        XCTAssertEqual(snapshot.requestsCount, 1)
        XCTAssertNotNil(snapshot.updatedAt)
    }

    func testToolLoopAccumulatesUsageAcrossMultipleRespondCalls() async throws {
        let firstResponse = """
        {
          "choices": [
            {
              "finish_reason": "tool_calls",
              "message": {
                "role": "assistant",
                "tool_calls": [
                  {
                    "id": "call_1",
                    "type": "function",
                    "function": {
                      "name": "echo_tool",
                      "arguments": "{\\\"text\\\":\\\"ok\\\"}"
                    }
                  }
                ]
              }
            }
          ],
          "created": 1,
          "model": "test-model",
          "usage": {
            "prompt_tokens": 8,
            "completion_tokens": 3,
            "total_tokens": 11,
            "completion_tokens_details": {
              "reasoning_tokens": 1
            }
          }
        }
        """

        let secondResponse = makeChatResponseJSON(
            content: "done",
            usage: makeUsageJSON(prompt: 6, completion: 4, total: 10, reasoning: 0)
        )

        let client = UsageSequenceClient(responses: [firstResponse, secondResponse])
        let session = SKILanguageModelSession(client: client, tools: [EchoTool()])

        _ = try await session.respond(to: "run tool")
        let snapshot = await session.tokenUsageSnapshot()

        XCTAssertEqual(snapshot.promptTokens, 14)
        XCTAssertEqual(snapshot.completionTokens, 7)
        XCTAssertEqual(snapshot.totalTokens, 21)
        XCTAssertEqual(snapshot.reasoningTokens, 1)
        XCTAssertEqual(snapshot.requestsCount, 2)
    }

    func testStreamingAccumulatesUsageFromUsageChunk() async throws {
        let session = SKILanguageModelSession(client: StreamingUsageClient())

        let stream = try await session.streamResponse(to: "stream")
        for try await _ in stream {
            // consume all
        }

        let snapshot = await session.tokenUsageSnapshot()
        XCTAssertEqual(snapshot.promptTokens, 12)
        XCTAssertEqual(snapshot.completionTokens, 7)
        XCTAssertEqual(snapshot.totalTokens, 19)
        XCTAssertEqual(snapshot.reasoningTokens, 2)
        XCTAssertEqual(snapshot.requestsCount, 1)
    }

    func testResetTokenUsageClearsCounters() async throws {
        let client = UsageSequenceClient(
            responses: [
                makeChatResponseJSON(content: "hello", usage: makeUsageJSON(prompt: 3, completion: 2, total: 5, reasoning: 1))
            ]
        )
        let session = SKILanguageModelSession(client: client)

        _ = try await session.respond(to: "hi")
        await session.resetTokenUsage()
        let snapshot = await session.tokenUsageSnapshot()

        XCTAssertEqual(snapshot.promptTokens, 0)
        XCTAssertEqual(snapshot.completionTokens, 0)
        XCTAssertEqual(snapshot.totalTokens, 0)
        XCTAssertEqual(snapshot.reasoningTokens, 0)
        XCTAssertEqual(snapshot.requestsCount, 0)
        XCTAssertNil(snapshot.updatedAt)
    }

    func testAgentSessionStatsContainsTokenUsage() async throws {
        let client = UsageSequenceClient(
            responses: [
                makeChatResponseJSON(content: "agent", usage: makeUsageJSON(prompt: 9, completion: 4, total: 13, reasoning: 2))
            ]
        )
        let agentSession = SKIAgentSession(client: client)

        _ = try await agentSession.prompt("hello")
        let stats = await agentSession.stats()

        XCTAssertEqual(stats.tokenUsage.promptTokens, 9)
        XCTAssertEqual(stats.tokenUsage.completionTokens, 4)
        XCTAssertEqual(stats.tokenUsage.totalTokens, 13)
        XCTAssertEqual(stats.tokenUsage.reasoningTokens, 2)
        XCTAssertEqual(stats.tokenUsage.requestsCount, 1)
    }
}

private final actor UsageSequenceClient: SKILanguageModelClient {
    private let responses: [String]
    private let httpResponse = HTTPResponse(status: .ok)
    private var index: Int = 0

    init(responses: [String]) {
        self.responses = responses
    }

    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        let current = min(index, responses.count - 1)
        let json = responses[current]
        index += 1
        return try SKIResponse(httpResponse: httpResponse, data: Data(json.utf8))
    }

    func streamingRespond(_ body: ChatRequestBody) async throws -> SKIResponseStream {
        let response = try await respond(body)
        return SKIResponseStream {
            AsyncThrowingStream { continuation in
                if let choice = response.content.choices.first {
                    continuation.yield(
                        SKIResponseChunk(
                            text: choice.message.content,
                            finishReason: choice.finishReason,
                            role: choice.message.role
                        )
                    )
                }
                continuation.finish()
            }
        }
    }
}

private struct StreamingUsageClient: SKILanguageModelClient {
    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        let json = makeChatResponseJSON(content: "fallback", usage: makeUsageJSON(prompt: 0, completion: 0, total: 0, reasoning: 0))
        return try SKIResponse(httpResponse: HTTPResponse(status: .ok), data: Data(json.utf8))
    }

    func streamingRespond(_ body: ChatRequestBody) async throws -> SKIResponseStream {
        XCTAssertEqual(body.streamOptions?.includeUsage, true)
        return SKIResponseStream {
            AsyncThrowingStream { continuation in
                continuation.yield(SKIResponseChunk(text: "partial", role: "assistant"))
                continuation.yield(
                    SKIResponseChunk(
                        usage: decodeUsage(makeUsageJSON(prompt: 12, completion: 7, total: 19, reasoning: 2))
                    )
                )
                continuation.finish()
            }
        }
    }
}

private struct EchoTool: SKITool {
    let name = "echo_tool"
    let description = "echo"

    @Schemable
    struct Arguments: Codable {
        let text: String
    }

    struct Output: Codable {
        let echoed: String
    }

    func call(_ arguments: Arguments) async throws -> Output {
        Output(echoed: arguments.text)
    }
}

private func makeUsageJSON(prompt: Int, completion: Int, total: Int, reasoning: Int) -> String {
    """
    {
      "prompt_tokens": \(prompt),
      "completion_tokens": \(completion),
      "total_tokens": \(total),
      "completion_tokens_details": {
        "reasoning_tokens": \(reasoning)
      }
    }
    """
}

private func makeChatResponseJSON(content: String, usage: String) -> String {
    """
    {
      "choices": [
        {
          "finish_reason": "stop",
          "message": {
            "role": "assistant",
            "content": "\(content)"
          }
        }
      ],
      "created": 1,
      "model": "test-model",
      "usage": \(usage)
    }
    """
}

private func decodeUsage(_ json: String) -> ChatUsage {
    let data = Data(json.utf8)
    return try! JSONDecoder().decode(ChatUsage.self, from: data)
}
