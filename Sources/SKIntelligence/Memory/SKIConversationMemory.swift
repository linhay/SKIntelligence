// SKIConversationMemory.swift
// SKIntelligence
//
// Simple FIFO memory that maintains a fixed number of recent messages.

import Foundation

// MARK: - SKIConversationMemory

/// A simple FIFO memory that maintains a fixed number of recent messages.
///
/// `SKIConversationMemory` is the most basic memory implementation, storing
/// the N most recent messages. When the limit is exceeded, the oldest
/// messages are automatically removed.
///
/// ## Usage
///
/// ```swift
/// let memory = SKIConversationMemory(maxMessages: 50)
/// await memory.add(.user("Hello"))
/// await memory.add(.assistant("Hi there!"))
/// let messages = await memory.context(for: "greeting", maxMessages: 10)
/// ```
///
/// ## Thread Safety
///
/// As an actor, `SKIConversationMemory` is automatically thread-safe.
/// All operations are serialized through the actor's executor.
public actor SKIConversationMemory: SKIMemory {

    /// Maximum number of messages to retain.
    public let maxMessages: Int

    public var count: Int {
        messages.count
    }

    /// Whether the memory contains no messages.
    public var isEmpty: Bool {
        messages.isEmpty
    }

    /// Internal message storage.
    private var messages: [SKIMemoryMessage] = []

    /// Creates a new conversation memory.
    ///
    /// - Parameter maxMessages: Maximum messages to retain (default: 100).
    public init(maxMessages: Int = 100) {
        self.maxMessages = max(1, maxMessages)
    }

    // MARK: - SKIMemory Conformance

    public func add(_ message: SKIMemoryMessage) async {
        messages.append(message)

        // Trim oldest messages if over limit
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }

    public func context(for _: String, maxMessages limit: Int?) async -> [SKIMemoryMessage] {
        guard let limit = limit else {
            return messages
        }
        return Array(messages.suffix(min(limit, messages.count)))
    }

    public func allMessages() async -> [SKIMemoryMessage] {
        messages
    }

    public func clear() async {
        messages.removeAll()
    }
}

// MARK: - Batch Operations

extension SKIConversationMemory {
    /// Adds multiple messages at once.
    ///
    /// More efficient than adding messages individually when importing
    /// conversation history.
    ///
    /// - Parameter newMessages: Messages to add in order.
    public func addAll(_ newMessages: [SKIMemoryMessage]) async {
        messages.append(contentsOf: newMessages)

        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }

    /// Returns the most recent N messages.
    ///
    /// - Parameter n: Number of messages to return.
    /// - Returns: Array of recent messages (may be fewer than N if memory has less).
    public func getRecentMessages(_ n: Int) async -> [SKIMemoryMessage] {
        Array(messages.suffix(min(n, messages.count)))
    }

    /// Returns the oldest N messages.
    ///
    /// - Parameter n: Number of messages to return.
    /// - Returns: Array of oldest messages (may be fewer than N if memory has less).
    public func getOldestMessages(_ n: Int) async -> [SKIMemoryMessage] {
        Array(messages.prefix(min(n, messages.count)))
    }
}

// MARK: - Query Operations

extension SKIConversationMemory {
    /// Returns the most recent message, if any.
    public var lastMessage: SKIMemoryMessage? {
        messages.last
    }

    /// Returns the first message, if any.
    public var firstMessage: SKIMemoryMessage? {
        messages.first
    }

    /// Returns messages matching a predicate.
    ///
    /// - Parameter predicate: Closure to test each message.
    /// - Returns: Array of messages where predicate returns true.
    public func filter(_ predicate: @Sendable (SKIMemoryMessage) -> Bool) async
        -> [SKIMemoryMessage]
    {
        messages.filter(predicate)
    }

    /// Returns messages with a specific role.
    ///
    /// - Parameter role: The role to filter by.
    /// - Returns: Array of messages with the specified role.
    public func messages(withRole role: SKIMemoryMessage.Role) async -> [SKIMemoryMessage] {
        messages.filter { $0.role == role }
    }
}
