//
//  SKITranscript.swift
//  SKIntelligence
//
//  Created by linhey on 11/4/25.
//

import Foundation

public actor SKITranscript {
    
    public typealias OrganizeEntriesAction = (_ entries: [Entry]) async throws -> [Entry]
    
    public struct ToolOutput {
        let content: ChatRequestBody.Message.MessageContent<String, [String]>
        let toolCall: ChatRequestBody.Message.ToolCall
    }
    
    public enum Entry {
        case prompt(ChatRequestBody.Message)
        case message(ChatRequestBody.Message)
        case response(ChatRequestBody.Message)
        
        case toolCalls(ChatRequestBody.Message.ToolCall)
        case toolOutput(ToolOutput)
    }
    
    public private(set) var entries: [Entry] = []
    public private(set) var organizeEntries: OrganizeEntriesAction?
    
    public init() {}
    
}

public extension SKITranscript {
    
    func runOrganizeEntries() async throws {
        if let entries = try await organizeEntries?(entries) {
            self.entries = entries
        }
    }
    
    /// 整理记录
    func setOrganizeEntries(_ block: OrganizeEntriesAction?) {
        organizeEntries = block
    }
    
}

public extension SKITranscript {
    
    func messages() async throws -> [ChatRequestBody.Message] {
        var list = [ChatRequestBody.Message]()
        for entry in self.entries {
            switch entry {
            case .message(let message), .response(let message), .prompt(let message):
                list.append(message)
            case .toolCalls(let toolCall):
                list.append(.assistant(toolCalls: [toolCall]))
            case .toolOutput(let toolOutput):
                list.append(.tool(content: toolOutput.content, toolCallID: toolOutput.toolCall.id))
            }
        }
        return list
    }
    
}

public extension SKITranscript {
    
    /// Appends a single entry to the transcript.
    func append(entry: Entry) {
        entries.append(entry)
    }
    
    func append(toolOutput entry: ToolOutput) {
        append(entry: .toolOutput(entry))
    }
    
    func append(toolCalls entry: ChatRequestBody.Message.ToolCall) {
        append(entry: .toolCalls(entry))
    }
    
    func append(message entry: ChatRequestBody.Message) {
        append(entry: .message(entry))
    }
    
    func append(prompt entry: ChatRequestBody.Message) {
        append(entry: .prompt(entry))
    }
    
    func append(response entry: ChatRequestBody.Message) {
        append(entry: .response(entry))
    }
    
    /// Appends multiple entries to the transcript.
    func append<S>(contentsOf newEntries: S) where S: Sequence, S.Element == Entry {
        for entry in newEntries {
            append(entry: entry)
        }
    }
    
}

extension SKITranscript {
    
    public subscript(_ index: Int) -> Entry {
        entries[index]
    }
    
    public var startIndex: Int {
        entries.startIndex
    }
    
    public var endIndex: Int {
        entries.endIndex
    }
    
}
