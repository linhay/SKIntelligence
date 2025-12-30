// SKISummaryMemory.swift
// SKIntelligence
//
// Memory that automatically summarizes old messages to compress history.

import Foundation

// MARK: - SKISummaryMemory

/// Memory that automatically summarizes old messages to compress history.
///
/// `SKISummaryMemory` maintains a summary of older conversation history
/// while keeping recent messages intact. When the message count exceeds
/// a threshold, older messages are summarized using the provided `SKISummarizer`.
///
/// ## Architecture
///
/// ```
/// [Summary of messages 1-50] + [Recent messages 51-100]
/// ```
///
/// ## Fallback Behavior
///
/// If the summarizer is unavailable, falls back to truncation to maintain functionality.
///
/// ## Usage
///
/// ```swift
/// let memory = SKISummaryMemory(
///     configuration: .init(recentMessageCount: 20, summarizationThreshold: 50)
/// )
/// await memory.add(.user("Hello"))
/// // When messages exceed 50, older ones are summarized
/// ```
public actor SKISummaryMemory: SKIMemory {

    // MARK: - Configuration

    /// Configuration for summary memory behavior.
    public struct Configuration: Sendable {
        /// Default configuration.
        public static let `default` = Configuration()

        /// Number of recent messages to keep unsummarized.
        public let recentMessageCount: Int

        /// Message count threshold that triggers summarization.
        public let summarizationThreshold: Int

        /// Maximum character length for the summary.
        public let summaryMaxLength: Int

        /// Creates a summary memory configuration.
        ///
        /// - Parameters:
        ///   - recentMessageCount: Messages to keep intact (default: 20).
        ///   - summarizationThreshold: When to trigger summarization (default: 50).
        ///   - summaryMaxLength: Maximum summary length in characters (default: 2000).
        public init(
            recentMessageCount: Int = 20,
            summarizationThreshold: Int = 50,
            summaryMaxLength: Int = 2000
        ) {
            let enforcedRecentCount = max(5, recentMessageCount)
            self.recentMessageCount = enforcedRecentCount
            self.summarizationThreshold = max(enforcedRecentCount + 10, summarizationThreshold)
            self.summaryMaxLength = max(100, summaryMaxLength)
        }
    }

    // MARK: - Properties

    /// Current configuration.
    public let configuration: Configuration

    public var count: Int {
        recentMessages.count
    }

    /// Whether the memory is empty (no recent messages and no summary).
    public var isEmpty: Bool {
        recentMessages.isEmpty && summary.isEmpty
    }

    /// Current summary text.
    public var currentSummary: String {
        summary
    }

    /// Whether a summary exists.
    public var hasSummary: Bool {
        !summary.isEmpty
    }

    /// Total messages processed (including summarized ones).
    public var totalMessagesProcessed: Int {
        totalMessagesAdded
    }

    // MARK: - Private State

    /// Summarization service.
    private let summarizer: any SKISummarizer

    /// Fallback summarizer when primary unavailable.
    private let fallbackSummarizer: any SKISummarizer

    /// Compressed summary of old messages.
    private var summary: String = ""

    /// Recent messages not yet summarized.
    private var recentMessages: [SKIMemoryMessage] = []

    /// Total messages ever added (for tracking).
    private var totalMessagesAdded: Int = 0

    // MARK: - Initialization

    /// Creates a new summary memory.
    ///
    /// - Parameters:
    ///   - configuration: Behavior configuration.
    ///   - summarizer: Primary summarization service.
    ///   - fallbackSummarizer: Fallback when primary unavailable.
    public init(
        configuration: Configuration = .default,
        summarizer: any SKISummarizer = SKITruncatingSummarizer.shared,
        fallbackSummarizer: any SKISummarizer = SKITruncatingSummarizer.shared
    ) {
        self.configuration = configuration
        self.summarizer = summarizer
        self.fallbackSummarizer = fallbackSummarizer
    }

    // MARK: - SKIMemory Conformance

    public func add(_ message: SKIMemoryMessage) async {
        recentMessages.append(message)
        totalMessagesAdded += 1

        // Check if summarization needed
        if recentMessages.count >= configuration.summarizationThreshold {
            await performSummarization()
        }
    }

    public func context(for _: String, maxMessages limit: Int?) async -> [SKIMemoryMessage] {
        // If we have a summary, include it as a system message at the start
        var result: [SKIMemoryMessage] = []

        if !summary.isEmpty {
            result.append(.system("[Previous conversation summary]: \(summary)"))
        }

        if let limit = limit {
            let availableSlots = max(0, limit - (summary.isEmpty ? 0 : 1))
            result.append(contentsOf: recentMessages.suffix(availableSlots))
        } else {
            result.append(contentsOf: recentMessages)
        }

        return result
    }

    public func allMessages() async -> [SKIMemoryMessage] {
        recentMessages
    }

    public func clear() async {
        summary = ""
        recentMessages.removeAll()
        totalMessagesAdded = 0
    }

    // MARK: - Private Methods

    private func performSummarization() async {
        // Keep only recent messages, summarize the rest
        let messagesToKeep = configuration.recentMessageCount
        let toSummarize = Array(recentMessages.prefix(recentMessages.count - messagesToKeep))
        recentMessages = Array(recentMessages.suffix(messagesToKeep))

        guard !toSummarize.isEmpty else { return }

        // Format messages for summarization
        let formattedMessages = toSummarize.map { "[\($0.role.rawValue)]: \($0.content)" }

        // Combine with existing summary
        let textToSummarize: String
        if summary.isEmpty {
            textToSummarize = formattedMessages.joined(separator: "\n")
        } else {
            textToSummarize = """
                Previous summary:
                \(summary)

                Additional conversation:
                \(formattedMessages.joined(separator: "\n"))
                """
        }

        // Try primary summarizer, fall back if needed
        do {
            if await summarizer.isAvailable {
                summary = try await summarizer.summarize(
                    textToSummarize, maxLength: configuration.summaryMaxLength)
            } else {
                summary = try await fallbackSummarizer.summarize(
                    textToSummarize, maxLength: configuration.summaryMaxLength)
            }
        } catch {
            // On failure, use truncation as last resort
            if let truncated = try? await SKITruncatingSummarizer.shared.summarize(
                textToSummarize,
                maxLength: configuration.summaryMaxLength
            ) {
                summary = truncated
            } else {
                // Ultimate fallback: just prefix
                summary = String(textToSummarize.prefix(configuration.summaryMaxLength))
            }
        }
    }
}

// MARK: - Manual Summarization

extension SKISummaryMemory {
    /// Forces summarization even if threshold not reached.
    ///
    /// Useful when you know a conversation break is happening
    /// and want to compress before continuing.
    public func forceSummarize() async {
        guard recentMessages.count > configuration.recentMessageCount else { return }
        await performSummarization()
    }

    /// Sets a custom summary, replacing any existing one.
    ///
    /// - Parameter newSummary: The summary text to use.
    public func setSummary(_ newSummary: String) async {
        summary = newSummary
    }

    /// Adds multiple messages at once.
    ///
    /// - Parameter newMessages: Messages to add in order.
    public func addAll(_ newMessages: [SKIMemoryMessage]) async {
        for message in newMessages {
            await add(message)
        }
    }
}
