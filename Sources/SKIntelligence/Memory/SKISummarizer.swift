// SKISummarizer.swift
// SKIntelligence
//
// Protocol for text summarization services.

import Foundation

// MARK: - SKISummarizer

/// Protocol for text summarization services.
///
/// Implementations can use LLM-based summarization, extractive methods,
/// or simple truncation as a fallback.
public protocol SKISummarizer: Sendable {
    /// Whether the summarizer is currently available.
    ///
    /// Some summarizers may depend on external services or models
    /// that might not always be accessible.
    var isAvailable: Bool { get async }

    /// Summarizes the given text within a maximum length.
    ///
    /// - Parameters:
    ///   - text: The text to summarize.
    ///   - maxLength: Maximum character length for the summary.
    /// - Returns: A summarized version of the text.
    /// - Throws: If summarization fails.
    func summarize(_ text: String, maxLength: Int) async throws -> String
}

// MARK: - SKITruncatingSummarizer

/// A simple summarizer that truncates text to fit within the limit.
///
/// This is a fallback implementation that simply takes the beginning
/// of the text. It's always available and never fails.
public struct SKITruncatingSummarizer: SKISummarizer {

    /// Shared instance for convenience.
    public static let shared = SKITruncatingSummarizer()

    /// Suffix to append when text is truncated.
    public let truncationSuffix: String

    /// Creates a truncating summarizer.
    ///
    /// - Parameter truncationSuffix: Text to append when truncating (default: "...").
    public init(truncationSuffix: String = "...") {
        self.truncationSuffix = truncationSuffix
    }

    public var isAvailable: Bool {
        get async { true }
    }

    public func summarize(_ text: String, maxLength: Int) async throws -> String {
        guard text.count > maxLength else {
            return text
        }

        let truncateAt = max(0, maxLength - truncationSuffix.count)
        return String(text.prefix(truncateAt)) + truncationSuffix
    }
}

// MARK: - SKISummarizerError

/// Errors that can occur during summarization.
public enum SKISummarizerError: Error, Sendable {
    /// The summarizer is not available.
    case unavailable

    /// Summarization failed with the given reason.
    case failed(reason: String)

    /// The input text is empty or invalid.
    case invalidInput
}

extension SKISummarizerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Summarizer is not available"
        case .failed(let reason):
            return "Summarization failed: \(reason)"
        case .invalidInput:
            return "Invalid input for summarization"
        }
    }
}
