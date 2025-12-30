// SKIMemoryStore.swift
// SKIntelligence
//
// Protocol defining session-based conversation history management.

import Foundation

// MARK: - SKIMemoryStore

/// Protocol for managing conversation session history with persistence.
///
/// `SKIMemoryStore` provides automatic conversation history management across agent runs,
/// enabling multi-turn conversations without manual history tracking.
///
/// Conforming types must be actors to ensure thread-safe access to session data.
///
/// ## Example Usage
/// ```swift
/// let store = SKIInMemoryStore()
///
/// // Add messages to store
/// try await store.addItem(.user("Hello!"))
/// try await store.addItem(.assistant("Hi there!"))
///
/// // Retrieve conversation history
/// let history = try await store.getAllItems()
///
/// // Get recent messages only
/// let recent = try await store.getItems(limit: 5)
/// ```
public protocol SKIMemoryStore: Actor, Sendable {
    /// Unique identifier for this store.
    ///
    /// Store IDs are used to distinguish between different conversation contexts
    /// and should remain constant throughout the store's lifecycle.
    ///
    /// This property is `nonisolated` because store IDs are immutable and can
    /// be safely accessed without actor isolation.
    nonisolated var storeId: String { get }

    /// Number of items currently stored.
    var itemCount: Int { get async }

    /// Whether the store contains no items.
    var isEmpty: Bool { get async }

    /// Retrieves the item count with proper error propagation.
    ///
    /// Unlike `itemCount`, this method throws on backend errors, allowing callers
    /// to distinguish between an empty store and a backend failure.
    ///
    /// - Returns: The number of items in the store.
    /// - Throws: `SKIMemoryStoreError` if the backend operation fails.
    func getItemCount() async throws -> Int

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
    /// - Throws: If retrieval fails due to underlying storage issues.
    func getItems(limit: Int?) async throws -> [SKIMemoryMessage]

    /// Adds items to the conversation history.
    ///
    /// Items are appended to the store in the order they appear in the array,
    /// maintaining the conversation's chronological sequence.
    ///
    /// - Parameter items: Messages to add to the store.
    /// - Throws: If storage operation fails.
    func addItems(_ items: [SKIMemoryMessage]) async throws

    /// Removes and returns the most recent item from the store.
    ///
    /// Follows LIFO (Last-In-First-Out) semantics, removing the last added item.
    /// This is useful for undoing the last message or implementing retry logic.
    ///
    /// - Returns: The removed message, or `nil` if the store is empty.
    /// - Throws: If removal operation fails.
    func popItem() async throws -> SKIMemoryMessage?

    /// Clears all items from this store.
    ///
    /// The store ID remains unchanged after clearing, allowing the store
    /// to be reused for new conversations.
    ///
    /// - Throws: If clear operation fails.
    func clearStore() async throws
}

// MARK: - Default Extension Methods

extension SKIMemoryStore {
    /// Adds a single item to the conversation history.
    ///
    /// This is a convenience method that wraps a single message in an array
    /// and delegates to `addItems(_:)`.
    ///
    /// - Parameter item: The message to add.
    /// - Throws: If storage operation fails.
    public func addItem(_ item: SKIMemoryMessage) async throws {
        try await addItems([item])
    }

    /// Retrieves all items from the store.
    ///
    /// This is a convenience method equivalent to calling `getItems(limit: nil)`.
    ///
    /// - Returns: All messages in chronological order.
    /// - Throws: If retrieval fails.
    public func getAllItems() async throws -> [SKIMemoryMessage] {
        try await getItems(limit: nil)
    }

    /// Default implementation that delegates to itemCount.
    ///
    /// Implementations should override this for proper error handling.
    public func getItemCount() async throws -> Int {
        await itemCount
    }
}

// MARK: - SKIMemoryStoreError

/// Errors that can occur during store operations.
public enum SKIMemoryStoreError: Error, Sendable {
    /// Failed to retrieve items from the store.
    /// - Parameters:
    ///   - reason: Human-readable description of what went wrong.
    ///   - underlyingError: The original error that caused the failure, if any.
    case retrievalFailed(reason: String, underlyingError: String? = nil)

    /// Failed to store items in the store.
    case storageFailed(reason: String, underlyingError: String? = nil)

    /// Failed to delete items from the store.
    case deletionFailed(reason: String, underlyingError: String? = nil)

    /// Store is in an invalid state.
    case invalidState(reason: String)

    /// Backend operation failed.
    case backendError(reason: String, underlyingError: String? = nil)
}

// MARK: Equatable

extension SKIMemoryStoreError: Equatable {
    public static func == (lhs: SKIMemoryStoreError, rhs: SKIMemoryStoreError) -> Bool {
        switch (lhs, rhs) {
        case (.retrievalFailed(let r1, let u1), .retrievalFailed(let r2, let u2)):
            r1 == r2 && u1 == u2
        case (.storageFailed(let r1, let u1), .storageFailed(let r2, let u2)):
            r1 == r2 && u1 == u2
        case (.deletionFailed(let r1, let u1), .deletionFailed(let r2, let u2)):
            r1 == r2 && u1 == u2
        case (.invalidState(let r1), .invalidState(let r2)):
            r1 == r2
        case (.backendError(let r1, let u1), .backendError(let r2, let u2)):
            r1 == r2 && u1 == u2
        default:
            false
        }
    }
}

// MARK: LocalizedError

extension SKIMemoryStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .retrievalFailed(let reason, let underlying):
            if let underlying {
                return "Failed to retrieve store items: \(reason). Underlying: \(underlying)"
            }
            return "Failed to retrieve store items: \(reason)"

        case .storageFailed(let reason, let underlying):
            if let underlying {
                return "Failed to store items: \(reason). Underlying: \(underlying)"
            }
            return "Failed to store items: \(reason)"

        case .deletionFailed(let reason, let underlying):
            if let underlying {
                return "Failed to delete store items: \(reason). Underlying: \(underlying)"
            }
            return "Failed to delete store items: \(reason)"

        case .invalidState(let reason):
            return "Store in invalid state: \(reason)"

        case .backendError(let reason, let underlying):
            if let underlying {
                return "Store backend error: \(reason). Underlying: \(underlying)"
            }
            return "Store backend error: \(reason)"
        }
    }
}
