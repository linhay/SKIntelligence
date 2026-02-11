//
//  SKIStreamingTests.swift
//  SKIntelligence
//
//  Created by linhey on 1/5/26.
//

import JSONSchema
import JSONSchemaBuilder
import XCTest

@testable import SKIntelligence

final class SKIStreamingTests: XCTestCase {

    // MARK: - ChatStreamResponseChunk Tests

    func testDecodeStreamChunk() throws {
        let json = """
            {
                "id": "chatcmpl-123",
                "object": "chat.completion.chunk",
                "created": 1234567890,
                "model": "gpt-4",
                "choices": [
                    {
                        "index": 0,
                        "delta": {
                            "content": "Hello"
                        },
                        "finish_reason": null
                    }
                ]
            }
            """.data(using: .utf8)!

        let chunk = try JSONDecoder().decode(ChatStreamResponseChunk.self, from: json)

        XCTAssertEqual(chunk.id, "chatcmpl-123")
        XCTAssertEqual(chunk.model, "gpt-4")
        XCTAssertEqual(chunk.choices.count, 1)
        XCTAssertEqual(chunk.choices.first?.delta.content, "Hello")
        XCTAssertNil(chunk.choices.first?.finishReason)
    }

    func testDecodeStreamChunkWithRole() throws {
        let json = """
            {
                "choices": [
                    {
                        "index": 0,
                        "delta": {
                            "role": "assistant"
                        }
                    }
                ]
            }
            """.data(using: .utf8)!

        let chunk = try JSONDecoder().decode(ChatStreamResponseChunk.self, from: json)

        XCTAssertEqual(chunk.choices.first?.delta.role, "assistant")
    }

    func testDecodeStreamChunkWithFinishReason() throws {
        let json = """
            {
                "choices": [
                    {
                        "index": 0,
                        "delta": {},
                        "finish_reason": "stop"
                    }
                ]
            }
            """.data(using: .utf8)!

        let chunk = try JSONDecoder().decode(ChatStreamResponseChunk.self, from: json)

        XCTAssertEqual(chunk.choices.first?.finishReason, "stop")
    }

    func testDecodeStreamChunkWithReasoning() throws {
        let json = """
            {
                "choices": [
                    {
                        "index": 0,
                        "delta": {
                            "reasoning_content": "Let me think..."
                        }
                    }
                ]
            }
            """.data(using: .utf8)!

        let chunk = try JSONDecoder().decode(ChatStreamResponseChunk.self, from: json)

        XCTAssertEqual(chunk.choices.first?.delta.reasoningContent, "Let me think...")
    }

    func testDecodeStreamChunkWithToolCalls() throws {
        let json = """
            {
                "choices": [
                    {
                        "index": 0,
                        "delta": {
                            "tool_calls": [
                                {
                                    "index": 0,
                                    "id": "call_abc123",
                                    "type": "function",
                                    "function": {
                                        "name": "get_weather",
                                        "arguments": "{\\"location\\":"
                                    }
                                }
                            ]
                        }
                    }
                ]
            }
            """.data(using: .utf8)!

        let chunk = try JSONDecoder().decode(ChatStreamResponseChunk.self, from: json)

        XCTAssertEqual(chunk.choices.first?.delta.toolCalls?.count, 1)
        XCTAssertEqual(chunk.choices.first?.delta.toolCalls?.first?.id, "call_abc123")
        XCTAssertEqual(chunk.choices.first?.delta.toolCalls?.first?.function?.name, "get_weather")
    }

    // MARK: - SKIResponseChunk Tests

    func testResponseChunkFromDelta() {
        let delta = DeltaContent(
            role: "assistant",
            content: "Hello",
            reasoningContent: "Thinking...",
            toolCalls: nil
        )

        let chunk = SKIResponseChunk(from: delta, finishReason: "stop")

        XCTAssertEqual(chunk.text, "Hello")
        XCTAssertEqual(chunk.reasoning, "Thinking...")
        XCTAssertEqual(chunk.role, "assistant")
        XCTAssertEqual(chunk.finishReason, "stop")
    }

    func testResponseChunkFromStreamChoice() {
        let choice = StreamChoice(
            index: 0,
            delta: DeltaContent(content: "World"),
            finishReason: nil
        )

        let chunk = SKIResponseChunk(from: choice)

        XCTAssertEqual(chunk.text, "World")
        XCTAssertNil(chunk.finishReason)
    }

    // MARK: - SKIResponseStream Tests

    func testResponseStreamIteration() async throws {
        let stream = SKIResponseStream {
            AsyncThrowingStream { continuation in
                continuation.yield(SKIResponseChunk(text: "Hello"))
                continuation.yield(SKIResponseChunk(text: " "))
                continuation.yield(SKIResponseChunk(text: "World"))
                continuation.finish()
            }
        }

        var result = ""
        for try await chunk in stream {
            result += chunk.text ?? ""
        }

        XCTAssertEqual(result, "Hello World")
    }

    func testResponseStreamTextConvenience() async throws {
        let stream = SKIResponseStream {
            AsyncThrowingStream { continuation in
                continuation.yield(SKIResponseChunk(text: "Hello"))
                continuation.yield(SKIResponseChunk(text: " World"))
                continuation.finish()
            }
        }

        let text = try await stream.text()
        XCTAssertEqual(text, "Hello World")
    }

    func testResponseStreamReasoningConvenience() async throws {
        let stream = SKIResponseStream {
            AsyncThrowingStream { continuation in
                continuation.yield(SKIResponseChunk(reasoning: "Step 1"))
                continuation.yield(SKIResponseChunk(reasoning: " Step 2"))
                continuation.finish()
            }
        }

        let reasoning = try await stream.reasoning()
        XCTAssertEqual(reasoning, "Step 1 Step 2")
    }

    func testResponseStreamErrorPropagation() async {
        struct TestError: Error {}

        let stream = SKIResponseStream {
            AsyncThrowingStream { continuation in
                continuation.yield(SKIResponseChunk(text: "Start"))
                continuation.finish(throwing: TestError())
            }
        }

        var receivedChunks = 0
        var didThrow = false

        do {
            for try await _ in stream {
                receivedChunks += 1
            }
        } catch {
            didThrow = true
        }

        XCTAssertEqual(receivedChunks, 1)
        XCTAssertTrue(didThrow)
    }

    // MARK: - ToolCallCollector Tests

    func testToolCallCollectorSingleCall() {
        let collector = ToolCallCollector()

        // First delta: id and function name
        collector.submit(
            delta: ToolCallDelta(
                index: 0,
                id: "call_123",
                type: "function",
                function: FunctionDelta(name: "get_weather", arguments: nil)
            ))

        // Following deltas: arguments in pieces
        collector.submit(
            delta: ToolCallDelta(
                index: 0,
                function: FunctionDelta(arguments: "{\"loc")
            ))
        collector.submit(
            delta: ToolCallDelta(
                index: 0,
                function: FunctionDelta(arguments: "ation\":")
            ))
        collector.submit(
            delta: ToolCallDelta(
                index: 0,
                function: FunctionDelta(arguments: "\"Beijing\"}")
            ))

        collector.finalizeCurrentToolCall()

        XCTAssertEqual(collector.pendingRequests.count, 1)
        XCTAssertEqual(collector.pendingRequests[0].id, "call_123")
        XCTAssertEqual(collector.pendingRequests[0].name, "get_weather")
        XCTAssertEqual(collector.pendingRequests[0].arguments, "{\"location\":\"Beijing\"}")
    }

    func testToolCallCollectorMultipleCalls() {
        let collector = ToolCallCollector()

        // First tool call
        collector.submit(
            delta: ToolCallDelta(
                index: 0,
                id: "call_1",
                function: FunctionDelta(name: "search", arguments: "{\"q\":\"test\"}")
            ))

        // Second tool call (different index triggers finalize)
        collector.submit(
            delta: ToolCallDelta(
                index: 1,
                id: "call_2",
                function: FunctionDelta(name: "translate", arguments: "{\"text\":\"hello\"}")
            ))

        collector.finalizeCurrentToolCall()

        XCTAssertEqual(collector.pendingRequests.count, 2)
        XCTAssertEqual(collector.pendingRequests[0].name, "search")
        XCTAssertEqual(collector.pendingRequests[1].name, "translate")
    }

    func testToolCallCollectorReset() {
        let collector = ToolCallCollector()

        collector.submit(
            delta: ToolCallDelta(
                index: 0,
                id: "call_1",
                function: FunctionDelta(name: "test", arguments: "{}")
            ))
        collector.finalizeCurrentToolCall()

        XCTAssertEqual(collector.pendingRequests.count, 1)

        collector.reset()

        XCTAssertEqual(collector.pendingRequests.count, 0)
    }

    func testSKIToolRequestArgumentsParsing() throws {
        let request = SKIToolRequest(
            id: "call_123",
            name: "get_weather",
            arguments: "{\"location\": \"Beijing\", \"unit\": \"celsius\"}"
        )

        let dict = try request.argumentsDictionary()

        XCTAssertEqual(dict["location"] as? String, "Beijing")
        XCTAssertEqual(dict["unit"] as? String, "celsius")
    }

    func testResponseStreamWithToolRequests() async throws {
        let toolRequests = [
            SKIToolRequest(id: "call_1", name: "search", arguments: "{\"q\":\"test\"}"),
            SKIToolRequest(id: "call_2", name: "translate", arguments: "{\"text\":\"hello\"}"),
        ]

        let stream = SKIResponseStream {
            AsyncThrowingStream { continuation in
                continuation.yield(SKIResponseChunk(text: "I will help you"))
                continuation.yield(SKIResponseChunk(toolRequests: toolRequests))
                continuation.finish()
            }
        }

        var receivedText = ""
        var receivedToolRequests: [SKIToolRequest] = []

        for try await chunk in stream {
            if let text = chunk.text {
                receivedText += text
            }
            if let tools = chunk.toolRequests {
                receivedToolRequests.append(contentsOf: tools)
            }
        }

        XCTAssertEqual(receivedText, "I will help you")
        XCTAssertEqual(receivedToolRequests.count, 2)
        XCTAssertEqual(receivedToolRequests[0].name, "search")
        XCTAssertEqual(receivedToolRequests[1].name, "translate")
    }

    // MARK: - Multi-Tool Streaming Integration Tests

    /// Tests streaming response with multiple tool executions
    func testMultiToolStreamingResponse() async throws {
        // Create mock tools
        let addTool = MockAddTool()
        let multiplyTool = MockMultiplyTool()

        // Create mock client that simulates multi-tool response
        let mockClient = MockMultiToolClient()

        // Create session with tools
        let session = SKILanguageModelSession(
            client: mockClient,
            tools: [addTool, multiplyTool]
        )

        // Collect results
        var receivedTexts: [String] = []
        var receivedToolRequests: [SKIToolRequest] = []
        var chunkCount = 0

        let stream = try await session.streamResponse(to: "Calculate 3+5 and 4*6")
        for try await chunk in stream {
            chunkCount += 1
            if let text = chunk.text {
                receivedTexts.append(text)
            }
            if let tools = chunk.toolRequests {
                receivedToolRequests.append(contentsOf: tools)
            }
        }

        // Verify tool calls were received
        XCTAssertEqual(receivedToolRequests.count, 2, "Should receive 2 tool requests")
        XCTAssertEqual(receivedToolRequests[0].name, "add")
        XCTAssertEqual(receivedToolRequests[1].name, "multiply")

        // Verify final text response
        let finalText = receivedTexts.joined()
        XCTAssertTrue(finalText.contains("8"), "Should contain add result (3+5=8)")
        XCTAssertTrue(finalText.contains("24"), "Should contain multiply result (4*6=24)")
    }

    /// Tests that tool execution errors are handled gracefully in streaming
    func testMultiToolStreamingWithError() async throws {
        let errorTool = MockErrorTool()
        let addTool = MockAddTool()

        let mockClient = MockToolErrorClient()
        let session = SKILanguageModelSession(
            client: mockClient,
            tools: [errorTool, addTool]
        )

        var receivedToolRequests: [SKIToolRequest] = []
        var receivedTexts: [String] = []

        let stream = try await session.streamResponse(to: "Test error handling")
        for try await chunk in stream {
            if let text = chunk.text {
                receivedTexts.append(text)
            }
            if let tools = chunk.toolRequests {
                receivedToolRequests.append(contentsOf: tools)
            }
        }

        // Should have called the error tool
        XCTAssertEqual(receivedToolRequests.first?.name, "error_tool")
        // Stream should complete without throwing
        XCTAssertFalse(receivedTexts.isEmpty)
    }

    /// Tests streaming with sequential tool calls (tool B depends on tool A's result)
    func testSequentialToolStreamingResponse() async throws {
        let addTool = MockAddTool()
        let multiplyTool = MockMultiplyTool()

        let mockClient = MockSequentialToolClient()
        let session = SKILanguageModelSession(
            client: mockClient,
            tools: [addTool, multiplyTool]
        )

        var toolCallOrder: [String] = []

        let stream = try await session.streamResponse(
            to: "First add 2+3, then multiply result by 4")
        for try await chunk in stream {
            if let tools = chunk.toolRequests {
                for tool in tools {
                    toolCallOrder.append(tool.name)
                }
            }
        }

        // Verify tools were called in order
        XCTAssertEqual(toolCallOrder.count, 2)
        XCTAssertEqual(toolCallOrder[0], "add")
        XCTAssertEqual(toolCallOrder[1], "multiply")
    }

    /// Tests streaming cancellation mid-tool-execution
    func testMultiToolStreamingCancellation() async throws {
        let slowTool = MockSlowTool()
        let mockClient = MockSlowToolClient()

        let session = SKILanguageModelSession(
            client: mockClient,
            tools: [slowTool]
        )

        let task = Task {
            var receivedChunks = 0
            let stream = try await session.streamResponse(to: "Do slow work")
            for try await _ in stream {
                receivedChunks += 1
                if receivedChunks >= 2 {
                    // Cancel after receiving some chunks
                    throw CancellationError()
                }
            }
            return receivedChunks
        }

        // Let it run briefly then cancel
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        task.cancel()

        // Task should complete (either with cancellation or normally)
        do {
            _ = try await task.value
        } catch is CancellationError {
            // Expected
        }
    }
}

// MARK: - Mock Tools for Testing

struct MockAddTool: SKITool {
    let name = "add"
    let description = "Adds two numbers"

    @Schemable
    struct Arguments: Codable {
        let a: Double
        let b: Double
    }

    struct Output: Codable {
        let result: Double
    }

    func call(_ arguments: Arguments) async throws -> Output {
        Output(result: arguments.a + arguments.b)
    }
}

struct MockMultiplyTool: SKITool {
    let name = "multiply"
    let description = "Multiplies two numbers"

    @Schemable
    struct Arguments: Codable {
        let a: Double
        let b: Double
    }

    struct Output: Codable {
        let result: Double
    }

    func call(_ arguments: Arguments) async throws -> Output {
        Output(result: arguments.a * arguments.b)
    }
}

struct MockErrorTool: SKITool {
    let name = "error_tool"
    let description = "Always throws an error"

    @Schemable
    struct Arguments: Codable {}

    struct Output: Codable {
        let result: String
    }

    func call(_ arguments: Arguments) async throws -> Output {
        throw NSError(
            domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Intentional error"]
        )
    }
}

struct MockSlowTool: SKITool {
    let name = "slow_tool"
    let description = "A slow tool for testing cancellation"

    @Schemable
    struct Arguments: Codable {}

    struct Output: Codable {
        let result: String
    }

    func call(_ arguments: Arguments) async throws -> Output {
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        return Output(result: "done")
    }
}

// MARK: - Mock Clients for Testing

/// Mock client that simulates calling two tools (add and multiply) in parallel
class MockMultiToolClient: SKILanguageModelClient {
    private var callCount = 0

    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        fatalError("Use streamingRespond instead")
    }

    func streamingRespond(_ body: ChatRequestBody) async throws -> SKIResponseStream {
        callCount += 1

        if callCount == 1 {
            // First call: return tool calls
            return SKIResponseStream {
                AsyncThrowingStream { continuation in
                    // Simulate streaming tool call deltas
                    continuation.yield(
                        SKIResponseChunk(
                            toolCallDeltas: [
                                ToolCallDelta(
                                    index: 0, id: "call_1", type: "function",
                                    function: FunctionDelta(
                                        name: "add", arguments: "{\"a\":3,\"b\":5}")),
                                ToolCallDelta(
                                    index: 1, id: "call_2", type: "function",
                                    function: FunctionDelta(
                                        name: "multiply", arguments: "{\"a\":4,\"b\":6}")),
                            ]
                        ))
                    continuation.finish()
                }
            }
        } else {
            // Second call: return final response
            return SKIResponseStream {
                AsyncThrowingStream { continuation in
                    continuation.yield(
                        SKIResponseChunk(text: "The sum is 8 and the product is 24."))
                    continuation.finish()
                }
            }
        }
    }
}

/// Mock client that simulates a tool throwing an error
class MockToolErrorClient: SKILanguageModelClient {
    private var callCount = 0

    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        fatalError("Use streamingRespond instead")
    }

    func streamingRespond(_ body: ChatRequestBody) async throws -> SKIResponseStream {
        callCount += 1

        if callCount == 1 {
            return SKIResponseStream {
                AsyncThrowingStream { continuation in
                    continuation.yield(
                        SKIResponseChunk(
                            toolCallDeltas: [
                                ToolCallDelta(
                                    index: 0, id: "call_err", type: "function",
                                    function: FunctionDelta(name: "error_tool", arguments: "{}"))
                            ]
                        ))
                    continuation.finish()
                }
            }
        } else {
            return SKIResponseStream {
                AsyncThrowingStream { continuation in
                    continuation.yield(SKIResponseChunk(text: "Error was handled gracefully."))
                    continuation.finish()
                }
            }
        }
    }
}

/// Mock client that simulates sequential tool calls (second depends on first)
class MockSequentialToolClient: SKILanguageModelClient {
    private var callCount = 0

    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        fatalError("Use streamingRespond instead")
    }

    func streamingRespond(_ body: ChatRequestBody) async throws -> SKIResponseStream {
        callCount += 1

        switch callCount {
        case 1:
            // First call: add tool
            return SKIResponseStream {
                AsyncThrowingStream { continuation in
                    continuation.yield(
                        SKIResponseChunk(
                            toolCallDeltas: [
                                ToolCallDelta(
                                    index: 0, id: "call_add", type: "function",
                                    function: FunctionDelta(
                                        name: "add", arguments: "{\"a\":2,\"b\":3}"))
                            ]
                        ))
                    continuation.finish()
                }
            }
        case 2:
            // Second call: multiply tool (using previous result)
            return SKIResponseStream {
                AsyncThrowingStream { continuation in
                    continuation.yield(
                        SKIResponseChunk(
                            toolCallDeltas: [
                                ToolCallDelta(
                                    index: 0, id: "call_mul", type: "function",
                                    function: FunctionDelta(
                                        name: "multiply", arguments: "{\"a\":5,\"b\":4}"))
                            ]
                        ))
                    continuation.finish()
                }
            }
        default:
            // Final response
            return SKIResponseStream {
                AsyncThrowingStream { continuation in
                    continuation.yield(SKIResponseChunk(text: "2+3=5, then 5*4=20"))
                    continuation.finish()
                }
            }
        }
    }
}

/// Mock client for testing slow tool execution and cancellation
class MockSlowToolClient: SKILanguageModelClient {
    private var callCount = 0

    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        fatalError("Use streamingRespond instead")
    }

    func streamingRespond(_ body: ChatRequestBody) async throws -> SKIResponseStream {
        callCount += 1

        if callCount == 1 {
            return SKIResponseStream {
                AsyncThrowingStream { continuation in
                    continuation.yield(SKIResponseChunk(text: "Starting..."))
                    continuation.yield(
                        SKIResponseChunk(
                            toolCallDeltas: [
                                ToolCallDelta(
                                    index: 0, id: "call_slow", type: "function",
                                    function: FunctionDelta(name: "slow_tool", arguments: "{}"))
                            ]
                        ))
                    continuation.finish()
                }
            }
        } else {
            return SKIResponseStream {
                AsyncThrowingStream { continuation in
                    continuation.yield(SKIResponseChunk(text: "Completed after slow tool."))
                    continuation.finish()
                }
            }
        }
    }
}
