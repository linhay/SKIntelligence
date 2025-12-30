// SKIMemoryMessage.swift
// SKIntelligence
//
// Core message type for agent memory systems.

import Foundation

// MARK: - SKIMemoryMessage

/// Represents a single message in agent memory.
///
/// `SKIMemoryMessage` is the fundamental unit of conversation history,
/// storing the role, content, and metadata for each interaction.
public struct SKIMemoryMessage: Sendable, Codable, Identifiable, Equatable, Hashable {
    /// The role of the entity in a conversation.
    public enum Role: String, Sendable, Codable, CaseIterable {
        /// Message from the user/human.
        case user
        /// Message from the AI assistant.
        case assistant
        /// System instruction or context.
        case system
        /// Output from a tool execution.
        case tool
        /// Developer instruction (for o1 models).
        case developer
    }

    /// Unique identifier for this message.
    public let id: UUID

    /// The role of the entity that produced this message.
    public let role: Role

    /// The textual content of the message.
    public let content: String

    /// When this message was created.
    public let timestamp: Date

    /// Additional key-value metadata attached to this message.
    public let metadata: [String: String]

    /// Creates a new memory message.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID).
    ///   - role: The role of the message sender.
    ///   - content: The message content.
    ///   - timestamp: When the message was created (defaults to now).
    ///   - metadata: Additional key-value metadata.
    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

// MARK: - Convenience Factory Methods

extension SKIMemoryMessage {
    /// Creates a user message.
    ///
    /// - Parameters:
    ///   - content: The message content.
    ///   - metadata: Optional metadata.
    /// - Returns: A new message with user role.
    public static func user(_ content: String, metadata: [String: String] = [:]) -> SKIMemoryMessage
    {
        SKIMemoryMessage(role: .user, content: content, metadata: metadata)
    }

    /// Creates an assistant message.
    ///
    /// - Parameters:
    ///   - content: The message content.
    ///   - metadata: Optional metadata.
    /// - Returns: A new message with assistant role.
    public static func assistant(_ content: String, metadata: [String: String] = [:])
        -> SKIMemoryMessage
    {
        SKIMemoryMessage(role: .assistant, content: content, metadata: metadata)
    }

    /// Creates a system message.
    ///
    /// - Parameters:
    ///   - content: The message content.
    ///   - metadata: Optional metadata.
    /// - Returns: A new message with system role.
    public static func system(_ content: String, metadata: [String: String] = [:])
        -> SKIMemoryMessage
    {
        SKIMemoryMessage(role: .system, content: content, metadata: metadata)
    }

    /// Creates a tool result message.
    ///
    /// - Parameters:
    ///   - content: The tool output content.
    ///   - toolName: The name of the tool that produced this result.
    /// - Returns: A new message with tool role.
    public static func tool(_ content: String, toolName: String) -> SKIMemoryMessage {
        SKIMemoryMessage(role: .tool, content: content, metadata: ["tool_name": toolName])
    }

    /// Creates a developer message.
    ///
    /// - Parameters:
    ///   - content: The message content.
    ///   - metadata: Optional metadata.
    /// - Returns: A new message with developer role.
    public static func developer(_ content: String, metadata: [String: String] = [:])
        -> SKIMemoryMessage
    {
        SKIMemoryMessage(role: .developer, content: content, metadata: metadata)
    }
}

// MARK: - ChatRequestBody.Message Conversion

extension SKIMemoryMessage {
    /// Converts this memory message to a ChatRequestBody.Message.
    ///
    /// - Returns: The equivalent ChatRequestBody.Message.
    public func toChatMessage() -> ChatRequestBody.Message {
        switch role {
        case .user:
            return .user(content: .text(content), name: metadata["name"])
        case .assistant:
            return .assistant(content: .text(content), name: metadata["name"])
        case .system:
            return .system(content: .text(content), name: metadata["name"])
        case .developer:
            return .developer(content: .text(content), name: metadata["name"])
        case .tool:
            let toolCallId = metadata["tool_call_id"] ?? UUID().uuidString
            return .tool(content: .text(content), toolCallID: toolCallId)
        }
    }

    /// Creates a memory message from a ChatRequestBody.Message.
    ///
    /// - Parameter chatMessage: The chat message to convert.
    /// - Returns: A new SKIMemoryMessage, or nil if conversion is not possible.
    public init?(from chatMessage: ChatRequestBody.Message) {
        switch chatMessage {
        case .user(let content, let name):
            self.init(
                role: .user,
                content: Self.extractContent(from: content),
                metadata: name.map { ["name": $0] } ?? [:]
            )
        case .assistant(let content, let name, _, _):
            guard let content = content else {
                return nil
            }
            self.init(
                role: .assistant,
                content: Self.extractTextContent(from: content),
                metadata: name.map { ["name": $0] } ?? [:]
            )
        case .system(let content, let name):
            self.init(
                role: .system,
                content: Self.extractTextContent(from: content),
                metadata: name.map { ["name": $0] } ?? [:]
            )
        case .developer(let content, let name):
            self.init(
                role: .developer,
                content: Self.extractTextContent(from: content),
                metadata: name.map { ["name": $0] } ?? [:]
            )
        case .tool(let content, let toolCallID):
            self.init(
                role: .tool,
                content: Self.extractTextContent(from: content),
                metadata: ["tool_call_id": toolCallID]
            )
        }
    }

    private static func extractContent(
        from content: ChatRequestBody.Message.MessageContent<
            String, [ChatRequestBody.Message.ContentPart]
        >
    ) -> String {
        switch content {
        case .text(let text):
            return text
        case .parts(let parts):
            return parts.compactMap { part in
                if case .text(let text) = part {
                    return text
                }
                return nil
            }.joined(separator: "\n")
        }
    }

    private static func extractTextContent(
        from content: ChatRequestBody.Message.MessageContent<String, [String]>
    ) -> String {
        switch content {
        case .text(let text):
            return text
        case .parts(let parts):
            return parts.joined(separator: "\n")
        }
    }
}

// MARK: CustomStringConvertible

extension SKIMemoryMessage: CustomStringConvertible {
    public var description: String {
        "SKIMemoryMessage(\(role.rawValue): \"\(content.prefix(50))\(content.count > 50 ? "..." : "")\")"
    }
}
