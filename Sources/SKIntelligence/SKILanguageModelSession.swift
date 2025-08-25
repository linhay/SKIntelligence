//
//  File.swift
//  SKIntelligence
//
//  Created by linhey on 6/12/25.
//

import Foundation

public protocol SKILanguageModelTranscript {
    var history: [ChatRequestBody.Message] { get set }
}

public class SKILanguageModelSession: SKIChatSection {
   
    public struct Transcript: SKILanguageModelTranscript {
        public var history: [ChatRequestBody.Message] = []
        public init(history: [ChatRequestBody.Message] = []) {
            self.history = history
        }
    }
    
    public var isResponding: Bool = false
    public let client: SKILanguageModelClient
    public var transcript: SKILanguageModelTranscript
    private var tools = [String: any SKITool]()
    public init(client: SKILanguageModelClient,
                transcript: SKILanguageModelTranscript = Transcript(),
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
    
    func respond(to prompt: SKIPrompt) async throws -> sending String {
        
        var body = ChatRequestBody(messages: [])
        var messages = transcript.history
        messages.append(.user(content: .text(prompt.value), name: nil))
        body.messages = messages
        body.tools = enabledTools()
        
        client.editRequestBody(&body)
        var response = try await client.respond(body)
        
        while true {
            guard let message = response.content.choices.first?.message else {
                break
            }
            if let toolCalls = message.toolCalls {
                for toolCall in toolCalls {
                    guard let arguments = toolCall.function.argumentsRaw,
                          let tool = self.tools[toolCall.function.name] else {
                        continue
                    }
                    let toolOutput = try await tool.call(arguments)
                    body.messages.append(.assistant(content: nil,
                                                    name: nil,
                                                    refusal: nil,
                                                    toolCalls: [
                                                        .init(id: toolCall.id,
                                                              function: .init(name: tool.name, arguments: arguments))
                                                    ]))
                    body.messages.append(.tool(content: .text(toolOutput), toolCallID: toolCall.id))
                    body.tools = enabledTools()
                }
                response = try await client.respond(body)
            } else {
                break
            }
        }
        let result = extractReasoningContent(from: response.content.choices.first?.message)?.content ?? ""
        transcript.history = body.messages
        transcript.history.append(.assistant(content: .text(result),
                                             name: nil,
                                             refusal: nil,
                                             toolCalls: nil))
        return result
    }
    
    
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
