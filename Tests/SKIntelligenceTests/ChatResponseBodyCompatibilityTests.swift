import XCTest

@testable import SKIntelligence

final class ChatResponseBodyCompatibilityTests: XCTestCase {

    func testDecodeContentPartsConcatenatesText() throws {
        let response = try decode(
            """
            {
              "choices": [
                {
                  "finish_reason": "stop",
                  "message": {
                    "role": "assistant",
                    "content": [
                      { "type": "text", "text": "hello " },
                      { "type": "text", "text": "world" }
                    ]
                  }
                }
              ],
              "created": 0,
              "model": "compat-test"
            }
            """
        )

        XCTAssertEqual(response.choices.first?.message.content, "hello world")
    }

    func testDecodeContentEmptyArrayDoesNotFail() throws {
        let response = try decode(
            """
            {
              "choices": [
                {
                  "finish_reason": "stop",
                  "message": {
                    "role": "assistant",
                    "content": []
                  }
                }
              ],
              "created": 0,
              "model": "compat-test"
            }
            """
        )

        XCTAssertNil(response.choices.first?.message.content)
    }

    func testDecodeToolCallsSkipsInvalidEntriesAndKeepsValidOnes() throws {
        let response = try decode(
            """
            {
              "choices": [
                {
                  "finish_reason": "tool_calls",
                  "message": {
                    "role": "assistant",
                    "tool_calls": [
                      {
                        "id": "call_bad",
                        "type": "function",
                        "function": { "arguments": "{}" }
                      },
                      {
                        "id": "call_ok",
                        "type": "function",
                        "function": {
                          "name": "sum",
                          "arguments": "{\\"a\\":1,\\"b\\":2}"
                        }
                      }
                    ]
                  }
                }
              ],
              "created": 0,
              "model": "compat-test"
            }
            """
        )

        let toolCalls = try XCTUnwrap(response.choices.first?.message.toolCalls)
        XCTAssertEqual(toolCalls.count, 1)
        XCTAssertEqual(toolCalls.first?.id, "call_ok")
        XCTAssertEqual(toolCalls.first?.function.name, "sum")
        XCTAssertEqual(toolCalls.first?.function.arguments?["a"] as? Int, 1)
        XCTAssertEqual(toolCalls.first?.function.arguments?["b"] as? Int, 2)
    }

    func testDecodeToolCallsEmptyArrayNormalizesToNil() throws {
        let response = try decode(
            """
            {
              "choices": [
                {
                  "finish_reason": "tool_calls",
                  "message": {
                    "role": "assistant",
                    "tool_calls": []
                  }
                }
              ],
              "created": 0,
              "model": "compat-test"
            }
            """
        )

        XCTAssertNil(response.choices.first?.message.toolCalls)
    }

    func testDecodeFunctionArgumentsFromStringJSON() throws {
        let response = try decode(
            """
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
                          "name": "echo",
                          "arguments": "{\\"input\\":\\"42\\"}"
                        }
                      }
                    ]
                  }
                }
              ],
              "created": 0,
              "model": "compat-test"
            }
            """
        )

        let function = try XCTUnwrap(response.choices.first?.message.toolCalls?.first?.function)
        XCTAssertEqual(function.argumentsRaw, "{\"input\":\"42\"}")
        XCTAssertEqual(function.arguments?["input"] as? String, "42")
    }

    func testDecodeFunctionArgumentsFromObjectBuildsCanonicalRaw() throws {
        let response = try decode(
            """
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
                          "name": "echo",
                          "arguments": { "b": 2, "a": 1 }
                        }
                      }
                    ]
                  }
                }
              ],
              "created": 0,
              "model": "compat-test"
            }
            """
        )

        let function = try XCTUnwrap(response.choices.first?.message.toolCalls?.first?.function)
        XCTAssertEqual(function.arguments?["a"] as? Int, 1)
        XCTAssertEqual(function.arguments?["b"] as? Int, 2)
        XCTAssertEqual(function.argumentsRaw, "{\"a\":1,\"b\":2}")
    }

    func testDecodeFunctionArgumentsFromNonObjectJSONKeepsRawOnly() throws {
        let response = try decode(
            """
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
                          "name": "echo",
                          "arguments": [1, 2, 3]
                        }
                      }
                    ]
                  }
                }
              ],
              "created": 0,
              "model": "compat-test"
            }
            """
        )

        let function = try XCTUnwrap(response.choices.first?.message.toolCalls?.first?.function)
        XCTAssertNil(function.arguments)
        XCTAssertEqual(function.argumentsRaw, "[1,2,3]")
    }

    func testDecodeLegacyOpenAISampleStillWorks() throws {
        let response = try decode(
            """
            {
              "choices": [
                {
                  "finish_reason": "stop",
                  "message": {
                    "role": "assistant",
                    "content": "done"
                  }
                }
              ],
              "created": 123,
              "model": "gpt-4.1-mini"
            }
            """
        )

        XCTAssertEqual(response.created, 123)
        XCTAssertEqual(response.model, "gpt-4.1-mini")
        XCTAssertEqual(response.choices.first?.message.content, "done")
    }

    func testDecodeOfficialProviderFixtures() throws {
        let openAI = try decodeFixture("openai_cookbook_tool_call_response")
        XCTAssertEqual(openAI.model, "gpt-4o-2024-08-06")
        XCTAssertEqual(openAI.choices.first?.finishReason, "tool_calls")
        XCTAssertEqual(openAI.choices.first?.message.toolCalls?.first?.function.name, "get_n_day_weather_forecast")
        XCTAssertEqual(
            openAI.choices.first?.message.toolCalls?.first?.function.arguments?["location"] as? String,
            "Glasgow, SCT"
        )

        let deepSeek = try decodeFixture("deepseek_api_schema_tool_call_response")
        XCTAssertEqual(deepSeek.model, "deepseek-chat")
        XCTAssertEqual(deepSeek.choices.first?.finishReason, "tool_calls")
        XCTAssertEqual(deepSeek.choices.first?.message.reasoningContent, "string")
        XCTAssertEqual(deepSeek.choices.first?.message.toolCalls?.first?.function.name, "get_weather")

        let dashScope = try decodeFixture("dashscope_http_chat_response")
        XCTAssertEqual(dashScope.model, "qwen-plus")
        XCTAssertEqual(dashScope.choices.first?.finishReason, "stop")
        XCTAssertEqual(dashScope.choices.first?.message.content, "我是来自阿里云的大规模语言模型，我叫千问。")
    }

    func testDecodeRandomizedCompatibilityPayloadDoesNotThrow() throws {
        var rng = SeededGenerator(seed: 0x5A17_2026)
        for _ in 0..<20 {
            let contentVariant = Int.random(in: 0...4, using: &rng)
            let argumentsVariant = Int.random(in: 0...4, using: &rng)
            let toolCallsVariant = Int.random(in: 0...3, using: &rng)
            let payload = makePayload(
                contentVariant: contentVariant,
                argumentsVariant: argumentsVariant,
                toolCallsVariant: toolCallsVariant
            )

            XCTAssertNoThrow(try decode(payload))
        }
    }

    private func decode(_ json: String) throws -> ChatResponseBody {
        try JSONDecoder().decode(ChatResponseBody.self, from: Data(json.utf8))
    }

    private func decodeFixture(_ name: String) throws -> ChatResponseBody {
        let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "chat-response-compat"
        )
        ?? Bundle.module.url(
            forResource: "chat-response-compat/\(name)",
            withExtension: "json"
        )
        ?? Bundle.module.url(
            forResource: name,
            withExtension: "json"
        )
        let resolvedURL = try XCTUnwrap(url)
        let data = try Data(contentsOf: resolvedURL)
        return try JSONDecoder().decode(ChatResponseBody.self, from: data)
    }

    private func makePayload(contentVariant: Int, argumentsVariant: Int, toolCallsVariant: Int) -> String {
        let contentFragment: String = switch contentVariant {
        case 0:
            "\"content\": \"ok\""
        case 1:
            "\"content\": null"
        case 2:
            "\"content\": []"
        case 3:
            "\"content\": [{\"type\":\"text\",\"text\":\"a\"},{\"type\":\"text\",\"text\":\"b\"}]"
        default:
            "\"content\": [{\"type\":\"unknown\",\"payload\":1}]"
        }

        let argumentsFragment: String = switch argumentsVariant {
        case 0:
            "\"arguments\": \"{\\\"x\\\":1}\""
        case 1:
            "\"arguments\": {\"z\":3,\"y\":2}"
        case 2:
            "\"arguments\": [1,2]"
        case 3:
            "\"arguments\": true"
        default:
            "\"arguments\": null"
        }

        let toolCallsFragment: String = switch toolCallsVariant {
        case 0:
            "\"tool_calls\": [{\"id\":\"call_ok\",\"type\":\"function\",\"function\":{\"name\":\"f\",\(argumentsFragment)}}]"
        case 1:
            "\"tool_calls\": [{\"id\":\"call_bad\",\"type\":\"function\",\"function\":{\"arguments\":\"{}\"}},{\"id\":\"call_ok\",\"type\":\"function\",\"function\":{\"name\":\"f\",\(argumentsFragment)}}]"
        case 2:
            "\"tool_calls\": []"
        default:
            "\"tool_calls\": null"
        }

        return """
        {
          "choices": [
            {
              "finish_reason": "tool_calls",
              "message": {
                "role": "assistant",
                \(contentFragment),
                \(toolCallsFragment)
              }
            }
          ],
          "created": 0,
          "model": "compat-random"
        }
        """
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }
}
