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
    
    public init(client: SKILanguageModelClient,
                transcript: SKITranscript = SKITranscript(),
                tools: [any SKITool] = []) {
        self.client = client
        self.transcript = transcript
        for tool in tools {
            register(tool: tool)
        }
    }
    
}

// MARK: - Public API

public extension SKILanguageModelSession {

    /// Responds to a simple string prompt.
    nonisolated func respond(to prompt: String) async throws -> sending String {
        try await respond(to: SKIPrompt(stringLiteral: prompt))
    }

    /// Responds to a prompt with a custom stop condition.
    ///
    /// - Parameters:
    ///   - prompt: The user prompt.
    ///   - stopWhen: A closure that evaluates each transcript entry. If it returns a non-nil value,
    ///               the generation loop stops and returns that value.
    /// - Returns: The value returned by `stopWhen`, or `nil` if generation completed normally.
    nonisolated func respond<T>(to prompt: SKIPrompt, stopWhen: @Sendable @escaping (SKITranscript.Entry) -> T?) async throws -> sending T? {
        try Task.checkCancellation()
        
        let entry = SKITranscript.Entry.prompt(prompt.message)
        try await appendEntry(entry)
        if let value = stopWhen(entry) { return value }
        
        return try await runGenerationLoop(
            onEntry: { entry in
                if let value = stopWhen(entry) {
                    return .stop(value)
                }
                return .continue
            },
            finalizeTranscript: false
        )
    }

    /// Responds to a prompt and returns the model's response.
    nonisolated func respond(to prompt: SKIPrompt) async throws -> sending String {
        try Task.checkCancellation()
        
        try await appendEntry(.prompt(prompt.message))
        
        let result: String? = try await runGenerationLoop(
            onEntry: { _ in .continue },
            finalizeTranscript: true
        )
        
        return result ?? ""
    }
    
    /// Clears the conversation history while preserving system messages.
    func clear() async {
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

public extension SKILanguageModelSession {
    
    /// Registers a tool that the model can call.
    func register(tool: any SKITool) {
        tools[tool.name] = tool
    }
    
    /// Unregisters a tool by name.
    func unregister(toolNamed name: String) {
        tools.removeValue(forKey: name)
    }
    
    /// Returns the list of enabled tools in the format expected by the API.
    func enabledTools() -> [ChatRequestBody.Tool]? {
        var result = [ChatRequestBody.Tool]()
        for tool in self.tools.values where tool.isEnabled {
            result.append(.function(
                name: tool.name,
                description: tool.description,
                parameters: tool.schemaParameters,
                strict: true
            ))
        }
        return result.isEmpty ? nil : result
    }
    
}

// MARK: - Private Implementation

private extension SKILanguageModelSession {
    
    /// Result of processing a transcript entry during generation.
    enum EntryProcessingResult<T> {
        case `continue`
        case stop(T)
    }
    
    /// Helper to append entry (bridges nonisolated context to actor)
    func appendEntry(_ entry: SKITranscript.Entry) async throws {
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
    func runGenerationLoop<T>(
        onEntry: @Sendable @escaping (SKITranscript.Entry) async throws -> EntryProcessingResult<T>,
        finalizeTranscript: Bool
    ) async throws -> T? {
        var body = ChatRequestBody(messages: [])
        body.messages = try await transcript.messages()
        body.tools = enabledTools()
        
        client.editRequestBody(&body)
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
                          let tool = self.tools[toolCall.function.name] else {
                        continue
                    }
                    
                    let requestToolCall = ChatRequestBody.Message.ToolCall(
                        id: toolCall.id,
                        function: .init(name: tool.name, arguments: arguments)
                    )
                    
                    let toolCallEntry = SKITranscript.Entry.toolCalls(requestToolCall)
                    try await transcript.append(entry: toolCallEntry)
                    
                    if case .stop(let value) = try await onEntry(toolCallEntry) {
                        return value
                    }
                    
                    // Execute tool with error handling
                    let toolOutput: String
                    do {
                        toolOutput = try await tool.call(arguments)
                    } catch {
                        // Return error information to the model instead of failing
                        toolOutput = """
                        {"error": "Tool execution failed", "tool": "\(tool.name)", "message": "\(error.localizedDescription)"}
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
                try await transcript.runOrganizeEntries()
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
        
        if finalizeTranscript {
            try await transcript.runOrganizeEntries()
        }
        
        // For the simple respond case, we return the result as T (which is String)
        return result as? T
    }
    
    /// Extracts reasoning content from `<think>` tags if present.
    func extractReasoningContent(from message: ChoiceMessage?) -> ChoiceMessage? {
        guard let message = message,
              let content = message.content,
              let startRange = content.range(of: "<think>"),
              let endRange = content.range(of: "</think>", range: startRange.upperBound..<content.endIndex) else {
            return message
        }
        let reasoningContent = String(content[startRange.upperBound..<endRange.lowerBound])
        let remainingContent = String(content[..<startRange.lowerBound]) + String(content[endRange.upperBound...])
        return .init(
            content: remainingContent,
            reasoning: reasoningContent,
            reasoningContent: reasoningContent,
            role: message.role
        )
    }
    
}
