// SKIMemory.swift
// SKIntelligence
//
// Core protocol defining memory storage and retrieval for agents.

import Foundation

// MARK: - SKIMemory

/// Protocol defining memory storage and retrieval for agents.
///
/// `SKIMemory` provides the contract for storing conversation history
/// and retrieving relevant context for agent operations. All implementations
/// must be actors to ensure thread-safe access.
///
/// ## Conformance Requirements
///
/// - Must be an `actor` (inherited from protocol requirements)
/// - Must be `Sendable` for safe concurrent access
/// - All methods are implicitly `async` due to actor isolation
///
/// ## Example Implementation
///
/// ```swift
/// public actor MyCustomMemory: SKIMemory {
///     private var messages: [SKIMemoryMessage] = []
///
///     public func add(_ message: SKIMemoryMessage) async {
///         messages.append(message)
///     }
///
///     public func context(for query: String, maxMessages: Int?) async -> [SKIMemoryMessage] {
///         if let limit = maxMessages {
///             return Array(messages.suffix(limit))
///         }
///         return messages
///     }
///
///     public func allMessages() async -> [SKIMemoryMessage] {
///         messages
///     }
///
///     public func clear() async {
///         messages.removeAll()
///     }
///
///     public var count: Int { messages.count }
/// }
/// ```
public protocol SKIMemory: Actor, Sendable {
    /// The number of messages currently stored.
    var count: Int { get async }

    /// Whether the memory contains no messages.
    ///
    /// Implementations should provide an efficient check that avoids
    /// fetching all messages when possible.
    var isEmpty: Bool { get async }

    /// Adds a message to memory.
    ///
    /// - Parameter message: The message to store.
    func add(_ message: SKIMemoryMessage) async

    /// Retrieves context relevant to the query.
    ///
    /// The implementation determines how to select messages.
    /// Simple implementations may return recent messages; advanced ones
    /// may use semantic search or summarization.
    ///
    /// - Parameters:
    ///   - query: The query to find relevant context for.
    ///   - maxMessages: Maximum number of messages to return, nil for all.
    /// - Returns: An array of relevant messages.
    func context(for query: String, maxMessages: Int?) async -> [SKIMemoryMessage]

    /// Returns all messages currently in memory.
    ///
    /// - Returns: Array of all stored messages, typically in chronological order.
    func allMessages() async -> [SKIMemoryMessage]

    /// Removes all messages from memory.
    func clear() async
}

// MARK: - Default Extensions

extension SKIMemory {
    /// Retrieves all messages as context (convenience method).
    public func context() async -> [SKIMemoryMessage] {
        await context(for: "", maxMessages: nil)
    }

    /// Retrieves recent messages as context.
    ///
    /// - Parameter limit: Maximum number of messages to return.
    /// - Returns: Array of recent messages.
    public func recentContext(limit: Int) async -> [SKIMemoryMessage] {
        await context(for: "", maxMessages: limit)
    }
}

// MARK: - AnyMemory

/// Type-erased wrapper for any SKIMemory implementation.
///
/// Useful when you need to store different memory types in collections
/// or pass them through APIs that don't support generics.
///
/// ## Usage
///
/// ```swift
/// let conversation = SKIConversationMemory(maxMessages: 50)
/// let erased = SKIAnyMemory(conversation)
/// await erased.add(.user("Hello"))
/// ```
public actor SKIAnyMemory: SKIMemory {

    public var count: Int {
        get async {
            await _count()
        }
    }

    public var isEmpty: Bool {
        get async {
            await _isEmpty()
        }
    }

    /// Creates a type-erased wrapper around any SKIMemory.
    ///
    /// - Parameter memory: The memory implementation to wrap.
    public init(_ memory: some SKIMemory) {
        _add = { message in await memory.add(message) }
        _context = { query, limit in await memory.context(for: query, maxMessages: limit) }
        _allMessages = { await memory.allMessages() }
        _clear = { await memory.clear() }
        _count = { await memory.count }
        _isEmpty = { await memory.isEmpty }
    }

    public func add(_ message: SKIMemoryMessage) async {
        await _add(message)
    }

    public func context(for query: String, maxMessages: Int?) async -> [SKIMemoryMessage] {
        await _context(query, maxMessages)
    }

    public func allMessages() async -> [SKIMemoryMessage] {
        await _allMessages()
    }

    public func clear() async {
        await _clear()
    }

    private let _add: @Sendable (SKIMemoryMessage) async -> Void
    private let _context: @Sendable (String, Int?) async -> [SKIMemoryMessage]
    private let _allMessages: @Sendable () async -> [SKIMemoryMessage]
    private let _clear: @Sendable () async -> Void
    private let _count: @Sendable () async -> Int
    private let _isEmpty: @Sendable () async -> Bool
}
