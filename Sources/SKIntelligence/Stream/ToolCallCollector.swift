//
//  ToolCallCollector.swift
//  SKIntelligence
//
//  Created by linhey on 1/5/26.
//

import Foundation

/// A complete tool request accumulated from streaming deltas.
public struct SKIToolRequest: Sendable, Equatable {
    /// The tool call ID from the API
    public let id: String?
    /// The function name to call
    public let name: String
    /// The JSON arguments string
    public let arguments: String

    public init(id: String? = nil, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    /// Parse arguments as a dictionary
    public func argumentsDictionary() throws -> [String: Any] {
        guard let data = arguments.data(using: .utf8),
            let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw NSError(
                domain: "SKIToolRequest", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse arguments as JSON"])
        }
        return dict
    }
}

/// Collects streaming tool call deltas and accumulates them into complete tool requests.
///
/// Tool calls in OpenAI streaming API come in multiple chunks:
/// ```json
/// // First chunk: id and function name
/// {"delta": {"tool_calls": [{"index": 0, "id": "call_123", "function": {"name": "get_weather"}}]}}
///
/// // Following chunks: arguments in pieces
/// {"delta": {"tool_calls": [{"index": 0, "function": {"arguments": "{\"loc"}}]}}
/// {"delta": {"tool_calls": [{"index": 0, "function": {"arguments": "ation\":"}}]}}
/// {"delta": {"tool_calls": [{"index": 0, "function": {"arguments": "\"Beijing\"}"}}]}}
/// ```
///
/// This collector accumulates all pieces and produces complete `SKIToolRequest` objects.
public final class ToolCallCollector: @unchecked Sendable {
    private var functionName: String = ""
    private var functionArguments: String = ""
    private var toolCallID: String?
    private var currentIndex: Int?

    /// Accumulated complete tool requests
    public private(set) var pendingRequests: [SKIToolRequest] = []

    public init() {}

    /// Submit a tool call delta to be accumulated.
    /// - Parameter delta: The tool call delta from streaming
    public func submit(delta: ToolCallDelta) {
        // If index changed, finalize the previous tool call
        if currentIndex != nil && currentIndex != delta.index {
            finalizeCurrentToolCall()
        }

        currentIndex = delta.index

        // Collect ID (usually only in first delta)
        if let id = delta.id, !id.isEmpty {
            toolCallID = id
        }

        // Accumulate function name
        if let name = delta.function?.name, !name.isEmpty {
            functionName.append(name)
        }

        // Accumulate function arguments
        if let arguments = delta.function?.arguments {
            functionArguments.append(arguments)
        }
    }

    /// Finalize the current tool call and add to pending requests.
    public func finalizeCurrentToolCall() {
        guard !functionName.isEmpty || !functionArguments.isEmpty else {
            return
        }

        let request = SKIToolRequest(
            id: toolCallID,
            name: functionName,
            arguments: functionArguments
        )
        pendingRequests.append(request)

        // Reset for next tool call
        functionName = ""
        functionArguments = ""
        toolCallID = nil
    }

    /// Reset the collector state.
    public func reset() {
        functionName = ""
        functionArguments = ""
        toolCallID = nil
        currentIndex = nil
        pendingRequests = []
    }
}
