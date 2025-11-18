//
//  File.swift
//  SKIntelligence
//
//  Created by linhey on 6/12/25.
//

import Foundation

public class SKILanguageModelSession: SKIChatSection {

    public var isResponding: Bool = false
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

public extension SKILanguageModelSession {

    func respond(to prompt: String) async throws -> sending String {
       try await respond(to: SKIPrompt.init(stringLiteral: prompt))
    }

    func respond<T>(to prompt: SKIPrompt, stopWhen: (SKITranscript.Entry) -> T?) async throws -> sending T? {
        var body = ChatRequestBody(messages: [])
        
        var entry = SKITranscript.Entry.prompt(.user(content: .text(prompt.value), name: nil))
        try await transcript.append(entry: entry)
        if let value = stopWhen(entry) { return value }
        
        body.messages = try await transcript.messages()
        body.tools = enabledTools()
        
        client.editRequestBody(&body)
        var response = try await client.respond(body)
        var responseMessage: ChoiceMessage?
        
        while responseMessage == nil {
            guard let message = response.content.choices.first?.message else {
                break
            }
            if let toolCalls = message.toolCalls {
                for toolCall in toolCalls {
                    guard let arguments = toolCall.function.argumentsRaw,
                          let tool = self.tools[toolCall.function.name] else {
                        continue
                    }
                    let toolCall = ChatRequestBody.Message.ToolCall(id: toolCall.id, function: .init(name: tool.name, arguments: arguments))
                    
                    entry = .toolCalls(toolCall)
                    try await transcript.append(entry: entry)
                    if let value = stopWhen(entry) { return value }
                    
                    let toolOutput = try await tool.call(arguments)
                    entry = .toolOutput(.init(content: .text(toolOutput), toolCall: toolCall))
                    try await transcript.append(entry: entry)
                    if let value = stopWhen(entry) { return value }
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
        
        entry = .message(.assistant(content: .text(result)))
        try await transcript.append(entry: entry)
        if let value = stopWhen(entry) { return value }
        
        return nil
    }

    func respond(to prompt: SKIPrompt) async throws -> sending String {
        var body = ChatRequestBody(messages: [])
        try await transcript.append(prompt: .user(content: .text(prompt.value), name: nil))
        body.messages = try await transcript.messages()
        body.tools = enabledTools()
        
        client.editRequestBody(&body)
        var response = try await client.respond(body)
        var responseMessage: ChoiceMessage?
        
        while responseMessage == nil {
            guard let message = response.content.choices.first?.message else {
                break
            }
            if let toolCalls = message.toolCalls {
                for toolCall in toolCalls {
                    guard let arguments = toolCall.function.argumentsRaw,
                          let tool = self.tools[toolCall.function.name] else {
                        continue
                    }
                    let toolCall = ChatRequestBody.Message.ToolCall(id: toolCall.id, function: .init(name: tool.name, arguments: arguments))
                    try await transcript.append(toolCalls: toolCall)
                    let toolOutput = try await tool.call(arguments)
                    try await transcript.append(toolOutput: .init(content: .text(toolOutput), toolCall: toolCall))
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
        try await transcript.append(response: .assistant(content: .text(result)))
        try await transcript.runOrganizeEntries()
        return result
    }
    
    
}

public extension SKILanguageModelSession {
    
    func register(tool: any SKITool) {
        tools[tool.name] = tool
    }
    
    func enabledTools() -> [ChatRequestBody.Tool]? {
        var tools = [ChatRequestBody.Tool]()
        for tool in self.tools.values {
            tools.append(.function(name: tool.name,
                                   description: tool.description,
                                   parameters: tool.schemaParameters,
                                   strict: true))
        }
        return tools.isEmpty ? nil : tools
    }
    
}


private extension SKILanguageModelSession {
    
    func extractReasoningContent(from message: ChoiceMessage?) -> ChoiceMessage? {
        guard let message = message,
              let content = message.content,
              let startRange = content.range(of: "<think>"),
              let endRange = content.range(of: "</think>", range: startRange.upperBound..<content.endIndex) else {
            return message
        }
        let reasoningContent = String(content[startRange.upperBound..<endRange.lowerBound])
        let remainingContent = String(content[..<startRange.lowerBound]) + String(content[endRange.upperBound...])
        return .init(content: remainingContent, reasoning: reasoningContent, reasoningContent: reasoningContent, role: message.role)
    }
    
}
