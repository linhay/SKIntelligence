//
//  ChatStreamDelta.swift
//  SKIntelligence
//
//  Created by linhey on 1/5/26.
//

import Foundation

/// OpenAI streaming response chunk structure.
///
/// See: https://platform.openai.com/docs/api-reference/chat/streaming
public struct ChatStreamResponseChunk: Decodable, Sendable {
    public let id: String?
    public let object: String?
    public let created: Int?
    public let model: String?
    public let choices: [StreamChoice]
    public let usage: ChatUsage?

    public init(
        id: String? = nil,
        object: String? = nil,
        created: Int? = nil,
        model: String? = nil,
        choices: [StreamChoice] = [],
        usage: ChatUsage? = nil
    ) {
        self.id = id
        self.object = object
        self.created = created
        self.model = model
        self.choices = choices
        self.usage = usage
    }
}

/// A choice in a streaming response
public struct StreamChoice: Decodable, Sendable {
    public let index: Int
    public let delta: DeltaContent
    public let finishReason: String?

    private enum CodingKeys: String, CodingKey {
        case index
        case delta
        case finishReason = "finish_reason"
    }

    public init(index: Int = 0, delta: DeltaContent, finishReason: String? = nil) {
        self.index = index
        self.delta = delta
        self.finishReason = finishReason
    }
}

/// Delta content in a streaming chunk
public struct DeltaContent: Decodable, Sendable {
    public let role: String?
    public let content: String?
    public let reasoningContent: String?
    public let toolCalls: [ToolCallDelta]?

    private enum CodingKeys: String, CodingKey {
        case role
        case content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
    }

    public init(
        role: String? = nil,
        content: String? = nil,
        reasoningContent: String? = nil,
        toolCalls: [ToolCallDelta]? = nil
    ) {
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.toolCalls = toolCalls
    }
}

/// Tool call delta for streaming
public struct ToolCallDelta: Decodable, Sendable {
    public let index: Int
    public let id: String?
    public let type: String?
    public let function: FunctionDelta?

    public init(index: Int, id: String? = nil, type: String? = nil, function: FunctionDelta? = nil)
    {
        self.index = index
        self.id = id
        self.type = type
        self.function = function
    }
}

/// Function call delta for streaming
public struct FunctionDelta: Decodable, Sendable {
    public let name: String?
    public let arguments: String?

    public init(name: String? = nil, arguments: String? = nil) {
        self.name = name
        self.arguments = arguments
    }
}
