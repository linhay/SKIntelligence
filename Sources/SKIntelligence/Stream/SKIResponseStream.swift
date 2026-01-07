//
//  SKIResponseStream.swift
//  SKIntelligence
//
//  Created by linhey on 1/5/26.
//

import Foundation

/// A response chunk from streaming output.
///
/// Similar to Apple's FoundationModels partial response pattern.
public struct SKIResponseChunk: Sendable {
    /// Text content delta
    public let text: String?

    /// Reasoning content delta (for models that support it)
    public let reasoning: String?

    /// Raw tool call deltas (from client layer - needs accumulation)
    public let toolCallDeltas: [ToolCallDelta]?

    /// Complete tool requests (accumulated by session layer)
    public let toolRequests: [SKIToolRequest]?

    /// Tool execution results (tool name and JSON output)
    public let toolResults: [SKIToolResult]?

    /// Finish reason when generation completes
    public let finishReason: String?

    /// Role of the message (usually only in first chunk)
    public let role: String?

    /// References from search tools (title, url pairs)
    public let references: [SKIReference]?

    public init(
        text: String? = nil,
        reasoning: String? = nil,
        toolCallDeltas: [ToolCallDelta]? = nil,
        toolRequests: [SKIToolRequest]? = nil,
        toolResults: [SKIToolResult]? = nil,
        finishReason: String? = nil,
        role: String? = nil,
        references: [SKIReference]? = nil
    ) {
        self.text = text
        self.reasoning = reasoning
        self.toolCallDeltas = toolCallDeltas
        self.toolRequests = toolRequests
        self.toolResults = toolResults
        self.finishReason = finishReason
        self.role = role
        self.references = references
    }

    /// Create from a streaming delta (includes raw tool call deltas)
    public init(from delta: DeltaContent, finishReason: String? = nil) {
        self.text = delta.content
        self.reasoning = delta.reasoningContent
        self.toolCallDeltas = delta.toolCalls
        self.toolRequests = nil
        self.toolResults = nil
        self.finishReason = finishReason
        self.role = delta.role
        self.references = nil
    }

    /// Create from a complete stream choice
    public init(from choice: StreamChoice) {
        self.init(from: choice.delta, finishReason: choice.finishReason)
    }
}

/// Represents a tool execution result
public struct SKIToolResult: Sendable, Codable {
    public let toolName: String
    public let toolId: String?
    public let output: String

    public init(toolName: String, toolId: String?, output: String) {
        self.toolName = toolName
        self.toolId = toolId
        self.output = output
    }
}

/// A stream of response chunks conforming to AsyncSequence.
///
/// Usage:
/// ```swift
/// let stream = try await client.streamingRespond(body)
/// for try await chunk in stream {
///     print(chunk.text ?? "")
/// }
/// ```
public struct SKIResponseStream: AsyncSequence, Sendable {
    public typealias Element = SKIResponseChunk

    private let makeStream: @Sendable () -> AsyncThrowingStream<SKIResponseChunk, Error>

    public init(
        _ makeStream: @escaping @Sendable () -> AsyncThrowingStream<SKIResponseChunk, Error>
    ) {
        self.makeStream = makeStream
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: makeStream().makeAsyncIterator())
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: AsyncThrowingStream<SKIResponseChunk, Error>.AsyncIterator

        public mutating func next() async throws -> SKIResponseChunk? {
            try await iterator.next()
        }
    }
}

// MARK: - Convenience Extensions

extension SKIResponseStream {

    /// Collect all chunks and return the complete text
    public func text() async throws -> String {
        var result = ""
        for try await chunk in self {
            if let text = chunk.text {
                result += text
            }
        }
        return result
    }

    /// Collect all chunks and return complete reasoning text
    public func reasoning() async throws -> String {
        var result = ""
        for try await chunk in self {
            if let reasoning = chunk.reasoning {
                result += reasoning
            }
        }
        return result
    }
}
