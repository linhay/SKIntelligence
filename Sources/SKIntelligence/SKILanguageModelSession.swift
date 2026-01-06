//
//  File.swift
//  SKIntelligence
//
//  Created by linhey on 6/12/25.
//

import Foundation

/// A session for managing conversations with a language model.
///
/// `SKILanguageModelSession` handles the conversation loop, including automatic
/// tool calling and response extraction. It is thread-safe as it is implemented
/// as an actor.
public actor SKILanguageModelSession: SKIChatSection {

    public let client: SKILanguageModelClient
    public var transcript: SKITranscript

    private var tools = [String: any SKITool]()
    private var mcpTools = [String: SKIMCPTool]()

    public init(
        client: SKILanguageModelClient,
        transcript: SKITranscript = SKITranscript(),
        tools: [any SKITool] = []
    ) {
        self.client = client
        self.transcript = transcript
        for tool in tools {
            self.tools[tool.name] = tool
        }
    }

}

// MARK: - Public API

extension SKILanguageModelSession {

    /// Responds to a simple string prompt.
    public nonisolated func respond(to prompt: String) async throws -> sending String {
        try await respond(to: SKIPrompt(stringLiteral: prompt))
    }

    /// Responds to a prompt and returns the model's response.
    public nonisolated func respond(
        to prompt: SKIPrompt
    ) async throws -> sending String {
        try Task.checkCancellation()
        try await appendEntry(.prompt(prompt.message))
        let result: String? = try await runGenerationLoop(
            beforeRequests: nil,
            onEntry: { _ in .continue }
        )
        return result ?? ""
    }

    /// Responds to a prompt and returns the model's response.
    public nonisolated func respond<Response: Codable>(
        to prompt: SKIPrompt,
        type: Response.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> sending Response {
        try Task.checkCancellation()
        try await appendEntry(.prompt(prompt.message))
        let result: String? = try await runGenerationLoop { body in
            body.responseFormat = .jsonObject
        } onEntry: { entry in
            return .continue
        }
        guard let result = result, let data = result.data(using: .utf8) else {
            throw SKIToolError.serverError(statusCode: 400, message: "Empty response")
        }
        return try decoder.decode(type, from: data)
    }

    /// Responds to a simple string prompt with streaming output.
    ///
    /// Usage:
    /// ```swift
    /// for try await chunk in try await session.streamResponse(to: "Hello") {
    ///     print(chunk.text ?? "")
    /// }
    /// ```
    public nonisolated func streamResponse(to prompt: String) async throws -> SKIResponseStream {
        try await streamResponse(to: SKIPrompt(stringLiteral: prompt))
    }

    /// Responds to a prompt with streaming output.
    ///
    /// Returns an `SKIResponseStream` that yields chunks as they are generated.
    /// Tool calls are automatically executed, and the model continues generating.
    /// - Parameter prompt: The prompt to respond to
    /// - Returns: A stream of response chunks
    public nonisolated func streamResponse(to prompt: SKIPrompt) async throws -> SKIResponseStream {
        try Task.checkCancellation()
        try await appendEntry(.prompt(prompt.message))

        // Capture session reference for the streaming closure
        let session = self

        return SKIResponseStream {
            AsyncThrowingStream { continuation in
                Task {
                    do {
                        try await session.runStreamingGenerationLoop(continuation: continuation)
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    /// Internal streaming generation loop that handles tool execution.
    private func runStreamingGenerationLoop(
        continuation: AsyncThrowingStream<SKIResponseChunk, Error>.Continuation
    ) async throws {
        var body = ChatRequestBody(messages: [])
        body.messages = try await transcript.messages()
        body.tools = enabledTools()

        var shouldContinue = true

        while shouldContinue {
            try Task.checkCancellation()

            let rawStream = try await client.streamingRespond(body)
            let toolCollector = ToolCallCollector()
            var accumulatedText = ""

            // Process the stream
            for try await chunk in rawStream {
                // Accumulate tool call deltas
                if let deltas = chunk.toolCallDeltas {
                    for delta in deltas {
                        toolCollector.submit(delta: delta)
                    }
                }

                // Yield text/reasoning chunks immediately
                if chunk.text != nil || chunk.reasoning != nil {
                    let cleanChunk = SKIResponseChunk(
                        text: chunk.text,
                        reasoning: chunk.reasoning,
                        finishReason: chunk.finishReason,
                        role: chunk.role
                    )
                    continuation.yield(cleanChunk)

                    if let text = chunk.text {
                        accumulatedText += text
                    }
                }
            }

            // Finalize tool calls
            toolCollector.finalizeCurrentToolCall()

            if !toolCollector.pendingRequests.isEmpty {
                // Execute tools and continue
                for toolRequest in toolCollector.pendingRequests {
                    try Task.checkCancellation()

                    guard
                        self.tools[toolRequest.name] != nil
                            || self.mcpTools[toolRequest.name] != nil
                    else {
                        continue
                    }

                    // Yield tool request info to stream with enriched displayName
                    var enrichedRequest = toolRequest
                    if let tool = self.tools[toolRequest.name] {
                        enrichedRequest.displayName = try await tool.displayName(
                            for: toolRequest.arguments)
                    }
                    let toolChunk = SKIResponseChunk(
                        toolRequests: [enrichedRequest]
                    )
                    continuation.yield(toolChunk)

                    // Add tool call to transcript
                    let requestToolCall = ChatRequestBody.Message.ToolCall(
                        id: toolRequest.id ?? UUID().uuidString,
                        function: .init(name: toolRequest.name, arguments: toolRequest.arguments)
                    )
                    let toolCallEntry = SKITranscript.Entry.toolCalls(requestToolCall)
                    try await transcript.append(entry: toolCallEntry)

                    // Execute tool with error handling
                    let toolOutput: String
                    do {
                        if let tool = self.tools[toolRequest.name] {
                            toolOutput = try await tool.call(toolRequest.arguments)
                        } else if let mcpTool = self.mcpTools[toolRequest.name] {
                            let args = try? toolRequest.argumentsDictionary()
                            toolOutput = try await mcpTool.call(args)
                        } else {
                            toolOutput = ""
                        }
                    } catch {
                        toolOutput = """
                            {"error": "Tool execution failed", "tool": "\(toolRequest.name)", "message": "\(error.localizedDescription)"}
                            """
                    }

                    // Add tool output to transcript
                    let outputEntry = SKITranscript.Entry.toolOutput(
                        .init(content: .text(toolOutput), toolCall: requestToolCall)
                    )
                    try await transcript.append(entry: outputEntry)
                }

                // Continue with new request
                body.tools = enabledTools()
                body.messages = try await transcript.messages()
                shouldContinue = true
            } else {
                // No tool calls - we're done
                shouldContinue = false

                // Add final response to transcript
                if !accumulatedText.isEmpty {
                    let responseEntry = SKITranscript.Entry.message(
                        .assistant(content: .text(accumulatedText))
                    )
                    try await transcript.append(entry: responseEntry)
                }
            }
        }

        continuation.finish()
    }

    /// Clears the conversation history while preserving system messages.

    public func clear() async {
        let systemEntries = await transcript.entries.filter { entry in
            if case .message(let msg) = entry, msg.role == "system" {
                return true
            }
            if case .prompt(let msg) = entry, msg.role == "system" {
                return true
            }
            return false
        }
        await transcript.replaceEntries(systemEntries)
    }
}

// MARK: - Tool Management

extension SKILanguageModelSession {

    /// Registers a tool that the model can call.
    public func register(tool: any SKITool) {
        tools[tool.name] = tool
    }

    public func register(mcpTool: SKIMCPTool) {
        mcpTools[mcpTool.name] = mcpTool
    }

    public func register(mcpTools: [SKIMCPTool]) {
        for tool in mcpTools {
            register(mcpTool: tool)
        }
    }

    /// Unregisters a tool by name.
    public func unregister(toolNamed name: String) {
        tools.removeValue(forKey: name)
    }

    /// Returns the list of enabled tools in the format expected by the API.
    public func enabledTools() -> [ChatRequestBody.Tool]? {
        var result = [ChatRequestBody.Tool]()
        for tool in self.tools.values where tool.isEnabled {
            result.append(
                .function(
                    name: tool.name,
                    description: tool.description,
                    parameters: tool.schemaParameters,
                    strict: true
                ))
        }
        for tool in self.mcpTools.values {
            result.append(tool.definition)
        }
        return result.isEmpty ? nil : result
    }

}

// MARK: - Private Implementation

extension SKILanguageModelSession {

    public typealias BeforeRequests = @Sendable (_ body: inout ChatRequestBody) async throws -> Void
    public typealias OnEntry<T> =
        @Sendable (SKITranscript.Entry) async throws -> EntryProcessingResult<T>

    /// Result of processing a transcript entry during generation.
    public enum EntryProcessingResult<T> {
        case `continue`
        case stop(T)
    }

    /// Helper to append entry (bridges nonisolated context to actor)
    fileprivate func appendEntry(_ entry: SKITranscript.Entry) async throws {
        try await transcript.append(entry: entry)
    }

    /// The core generation loop that handles tool calls and response extraction.
    ///
    /// This method encapsulates the shared logic between different `respond` variants.
    ///
    /// - Parameters:
    ///   - onEntry: Called for each new transcript entry. Returns whether to continue or stop.
    ///   - finalizeTranscript: Whether to run `organizeEntries` after completion.
    /// - Returns: Either the stop value from `onEntry`, or the final response string.
    private func runGenerationLoop<T>(
        beforeRequests: BeforeRequests?,
        onEntry: @escaping OnEntry<T>
    ) async throws -> T? {
        var body = ChatRequestBody(messages: [])
        body.messages = try await transcript.messages()
        body.tools = enabledTools()
        try await beforeRequests?(&body)
        var response = try await client.respond(body)
        var responseMessage: ChoiceMessage?

        while responseMessage == nil {
            try Task.checkCancellation()

            guard let message = response.content.choices.first?.message else {
                break
            }

            if let toolCalls = message.toolCalls {
                for toolCall in toolCalls {
                    try Task.checkCancellation()

                    guard let arguments = toolCall.function.argumentsRaw,
                        self.tools[toolCall.function.name] != nil
                            || self.mcpTools[toolCall.function.name] != nil
                    else {
                        continue
                    }

                    let requestToolCall = ChatRequestBody.Message.ToolCall(
                        id: toolCall.id,
                        function: .init(name: toolCall.function.name, arguments: arguments)
                    )

                    let toolCallEntry = SKITranscript.Entry.toolCalls(requestToolCall)
                    try await transcript.append(entry: toolCallEntry)

                    if case .stop(let value) = try await onEntry(toolCallEntry) {
                        return value
                    }

                    // Execute tool with error handling
                    let toolOutput: String
                    do {
                        if let tool = self.tools[toolCall.function.name] {
                            toolOutput = try await tool.call(arguments)
                        } else if let mcpTool = self.mcpTools[toolCall.function.name] {
                            toolOutput = try await mcpTool.call(toolCall.function.arguments)
                        } else {
                            toolOutput = ""
                        }
                    } catch {
                        // Return error information to the model instead of failing
                        toolOutput = """
                            {"error": "Tool execution failed", "tool": "\(toolCall.function.name)", "message": "\(error.localizedDescription)"}
                            """
                    }

                    let outputEntry = SKITranscript.Entry.toolOutput(
                        .init(content: .text(toolOutput), toolCall: requestToolCall)
                    )
                    try await transcript.append(entry: outputEntry)

                    if case .stop(let value) = try await onEntry(outputEntry) {
                        return value
                    }
                }

                body.tools = enabledTools()
                body.messages = try await transcript.messages()
                response = try await client.respond(body)
            } else {
                responseMessage = message
            }
        }

        let result = extractReasoningContent(from: responseMessage)?.content ?? ""

        let responseEntry = SKITranscript.Entry.message(.assistant(content: .text(result)))
        try await transcript.append(entry: responseEntry)

        if case .stop(let value) = try await onEntry(responseEntry) {
            return value
        }

        // For the simple respond case, we return the result as T (which is String)
        return result as? T
    }

    /// Extracts reasoning content from `<think>` tags if present.
    fileprivate func extractReasoningContent(from message: ChoiceMessage?) -> ChoiceMessage? {
        guard let message = message,
            let content = message.content,
            let startRange = content.range(of: "<think>"),
            let endRange = content.range(
                of: "</think>", range: startRange.upperBound..<content.endIndex)
        else {
            return message
        }
        let reasoningContent = String(content[startRange.upperBound..<endRange.lowerBound])
        let remainingContent =
            String(content[..<startRange.lowerBound]) + String(content[endRange.upperBound...])
        return .init(
            content: remainingContent,
            reasoning: reasoningContent,
            reasoningContent: reasoningContent,
            role: message.role
        )
    }

}
