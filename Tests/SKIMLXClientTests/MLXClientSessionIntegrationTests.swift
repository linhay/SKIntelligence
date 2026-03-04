import Foundation
import JSONSchema
import JSONSchemaBuilder
import XCTest

@testable import SKIMLXClient
@testable import SKIntelligence

final class MLXClientSessionIntegrationTests: XCTestCase {
    func testSessionRespondConsumesMLXToolCall() async throws {
        let backend = ScriptedBackend(
            nonStreamingPlan: [
                [.toolCall(name: "add_numbers", arguments: ["a": 2, "b": 3]), .info(prompt: 12, completion: 8)],
                [.text("answer is 5"), .info(prompt: 6, completion: 4)],
            ],
            streamingPlan: []
        )
        let client = MLXClient(
            configuration: .init(modelID: "mock/model", toolCallEnabled: true),
            backend: backend
        )
        let session = SKILanguageModelSession(client: client, tools: [AddNumbersTool()])

        let result = try await session.respond(to: "2+3=?")
        let transcript = await session.transcript.entries
        let usage = await session.tokenUsageSnapshot()

        XCTAssertEqual(result, "answer is 5")
        XCTAssertEqual(usage.promptTokens, 18)
        XCTAssertEqual(usage.completionTokens, 12)
        XCTAssertTrue(
            transcript.contains(where: { entry in
                if case .toolCalls(let call) = entry {
                    return call.function.name == "add_numbers"
                }
                return false
            })
        )
        XCTAssertTrue(
            transcript.contains(where: { entry in
                if case .toolOutput(let output) = entry {
                    return output.contentString.contains("\"result\":5")
                }
                return false
            })
        )
    }

    func testSessionStreamConsumesMLXToolCallDelta() async throws {
        let backend = ScriptedBackend(
            nonStreamingPlan: [],
            streamingPlan: [
                [.toolCall(name: "echo_value", arguments: ["value": "ok"])],
                [.text("done"), .info(prompt: 4, completion: 3)],
            ]
        )
        let client = MLXClient(
            configuration: .init(modelID: "mock/model", toolCallEnabled: true),
            backend: backend
        )
        let session = SKILanguageModelSession(client: client, tools: [EchoValueTool()])

        let stream = try await session.streamResponse(to: "call tool")

        var text = ""
        var sawToolRequest = false
        var sawToolResult = false
        for try await chunk in stream {
            text += chunk.text ?? ""
            sawToolRequest = sawToolRequest || !(chunk.toolRequests ?? []).isEmpty
            sawToolResult = sawToolResult || !(chunk.toolResults ?? []).isEmpty
        }

        XCTAssertEqual(text, "done")
        XCTAssertTrue(sawToolRequest)
        XCTAssertTrue(sawToolResult)
    }
}

private actor ScriptedBackend: MLXClientBackend {
    private var nonStreamingPlan: [[MLXClientEvent]]
    private var streamingPlan: [[MLXClientEvent]]
    private var nonStreamingIndex = 0
    private var streamingIndex = 0

    init(nonStreamingPlan: [[MLXClientEvent]], streamingPlan: [[MLXClientEvent]]) {
        self.nonStreamingPlan = nonStreamingPlan
        self.streamingPlan = streamingPlan
    }

    func ensureLoaded(configuration: MLXClient.Configuration) async throws {}

    func generate(
        request: MLXClientRequest,
        configuration: MLXClient.Configuration
    ) async throws -> [MLXClientEvent] {
        defer { nonStreamingIndex += 1 }
        if nonStreamingIndex < nonStreamingPlan.count {
            return nonStreamingPlan[nonStreamingIndex]
        }
        return [.text("")]
    }

    func streamGenerate(
        request: MLXClientRequest,
        configuration: MLXClient.Configuration
    ) async throws -> AsyncThrowingStream<MLXClientEvent, Error> {
        let events: [MLXClientEvent]
        if streamingIndex < streamingPlan.count {
            events = streamingPlan[streamingIndex]
        } else {
            events = []
        }
        streamingIndex += 1

        return AsyncThrowingStream { continuation in
            Task {
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}

private struct AddNumbersTool: SKITool {
    let name = "add_numbers"
    let description = "Add two integers"

    @Schemable
    struct Arguments: Codable {
        let a: Int
        let b: Int
    }

    struct Output: Codable {
        let result: Int
    }

    func call(_ arguments: Arguments) async throws -> Output {
        .init(result: arguments.a + arguments.b)
    }
}

private struct EchoValueTool: SKITool {
    let name = "echo_value"
    let description = "Echo one string value"

    @Schemable
    struct Arguments: Codable {
        let value: String
    }

    struct Output: Codable {
        let echoed: String
    }

    func call(_ arguments: Arguments) async throws -> Output {
        .init(echoed: arguments.value)
    }
}
