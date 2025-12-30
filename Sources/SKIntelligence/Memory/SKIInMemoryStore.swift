// SKIInMemoryStore.swift
// SKIntelligence
//
// In-memory implementation of the SKIMemoryStore protocol.

import Foundation

// MARK: - SKIInMemoryStore

/// In-memory store implementation for testing and simple use cases.
///
/// `SKIInMemoryStore` stores conversation history in memory, providing
/// fast access for single-process applications. Data is lost when the
/// store is deallocated.
///
/// This implementation is ideal for:
/// - Unit testing and development
/// - Short-lived conversations
/// - Applications that don't require persistence
///
/// ## Thread Safety
/// As an actor, `SKIInMemoryStore` provides automatic thread-safe access
/// to all store data through Swift's actor isolation.
///
/// ## Example Usage
/// ```swift
/// // Create with auto-generated store ID
/// let store = SKIInMemoryStore()
///
/// // Or with a custom store ID
/// let customStore = SKIInMemoryStore(storeId: "user-123-chat")
///
/// // Add conversation messages
/// try await store.addItem(.user("What's the weather?"))
/// try await store.addItem(.assistant("It's sunny today!"))
///
/// // Retrieve recent history
/// let recent = try await store.getItems(limit: 10)
/// ```
public actor SKIInMemoryStore: SKIMemoryStore {

    /// Unique identifier for this store.
    nonisolated public let storeId: String

    // MARK: - SKIMemoryStore Protocol Properties

    /// Number of items currently stored.
    public var itemCount: Int {
        items.count
    }

    /// Whether the store contains no items.
    public var isEmpty: Bool {
        items.isEmpty
    }

    // MARK: - Private State

    /// Internal storage for messages.
    private var items: [SKIMemoryMessage] = []

    // MARK: - Initialization

    /// Creates a new in-memory store.
    ///
    /// - Parameter storeId: Unique identifier for the store.
    ///   Defaults to a new UUID string if not provided.
    public init(storeId: String = UUID().uuidString) {
        self.storeId = storeId
    }

    /// Retrieves the item count with proper error propagation.
    ///
    /// For in-memory stores, this operation cannot fail, so it simply
    /// returns the current item count.
    ///
    /// - Returns: The number of items in the store.
    public func getItemCount() async throws -> Int {
        items.count
    }

    // MARK: - SKIMemoryStore Protocol Methods

    /// Retrieves conversation history from the store.
    ///
    /// Items are returned in chronological order (oldest first).
    /// When a limit is specified, returns the most recent N items
    /// while still maintaining chronological order.
    ///
    /// - Parameter limit: Maximum number of items to retrieve.
    ///   - `nil`: Returns all items
    ///   - Positive value: Returns the last N items in chronological order
    ///   - Zero or negative: Returns an empty array
    /// - Returns: Array of messages in chronological order.
    public func getItems(limit: Int?) async throws -> [SKIMemoryMessage] {
        guard let limit else {
            return items
        }

        guard limit > 0 else {
            return []
        }

        // Return last N items in chronological order
        let startIndex = max(0, items.count - limit)
        return Array(items[startIndex...])
    }

    /// Adds items to the conversation history.
    ///
    /// Items are appended in the order they appear in the array,
    /// maintaining the conversation's chronological sequence.
    ///
    /// - Parameter newItems: Messages to add to the store.
    public func addItems(_ newItems: [SKIMemoryMessage]) async throws {
        items.append(contentsOf: newItems)
    }

    /// Removes and returns the most recent item from the store.
    ///
    /// Follows LIFO (Last-In-First-Out) semantics.
    ///
    /// - Returns: The removed message, or `nil` if the store is empty.
    public func popItem() async throws -> SKIMemoryMessage? {
        guard !items.isEmpty else {
            return nil
        }
        return items.removeLast()
    }

    /// Clears all items from this store.
    ///
    /// The store ID remains unchanged, allowing the store to be
    /// reused for new conversations.
    public func clearStore() async throws {
        items.removeAll()
    }
}
