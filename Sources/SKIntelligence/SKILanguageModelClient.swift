//
//  SKILanguageModelClient.swift
//  SKIntelligence
//
//  Created by linhey on 6/14/25.
//

import Foundation

public protocol SKILanguageModelClient {
    /// Responds to a chat request and returns the complete response.
    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody>

    /// Responds to a chat request with streaming output.
    ///
    /// Returns an `SKIResponseStream` that yields chunks as they are generated.
    /// - Parameter body: The chat request body
    /// - Returns: A stream of response chunks
    func streamingRespond(_ body: ChatRequestBody) async throws -> SKIResponseStream
}

extension SKILanguageModelClient {
    public func respond(_ build: (_ body: inout ChatRequestBody) -> Void) async throws
        -> sending SKIResponse<ChatResponseBody>
    {
        var requestBody = ChatRequestBody(messages: [])
        build(&requestBody)
        return try await respond(requestBody)
    }

    public func streamingRespond(_ build: (_ body: inout ChatRequestBody) -> Void) async throws
        -> SKIResponseStream
    {
        var requestBody = ChatRequestBody(messages: [])
        build(&requestBody)
        return try await streamingRespond(requestBody)
    }

    /// Default implementation: falls back to non-streaming respond and converts to single chunk
    public func streamingRespond(_ body: ChatRequestBody) async throws -> SKIResponseStream {
        let response = try await respond(body)
        return SKIResponseStream {
            AsyncThrowingStream { continuation in
                if let choice = response.content.choices.first {
                    let chunk = SKIResponseChunk(
                        text: choice.message.content,
                        reasoning: choice.message.reasoningContent ?? choice.message.reasoning,
                        toolCallDeltas: nil,
                        toolRequests: nil,
                        finishReason: choice.finishReason,
                        role: choice.message.role
                    )
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }
}
