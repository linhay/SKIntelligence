//
//  SKITranscript.swift
//  SKIntelligence
//
//  Created by linhey on 11/4/25.
//

import Foundation

public actor SKITranscript {
    
    public typealias OrganizeEntriesAction = @Sendable (_ entries: [Entry]) async throws -> [Entry]
    public typealias ObserveNewEntry = @Sendable (_ entry: Entry) async throws -> Void

    public struct ToolOutput {
        public let content: ChatRequestBody.Message.MessageContent<String, [String]>
        public let toolCall: ChatRequestBody.Message.ToolCall
        
        public init(content: ChatRequestBody.Message.MessageContent<String, [String]>, toolCall: ChatRequestBody.Message.ToolCall) {
            self.content = content
            self.toolCall = toolCall
        }
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
    public private(set) var observeNewEntry: ObserveNewEntry?
    public init() {}
    
}

public extension SKITranscript {
    
    func replaceEntries(_ newEntries: [Entry]) {
        entries = newEntries
    }
    
    func runOrganizeEntries() async throws {
        if let entries = try await organizeEntries?(entries) {
            self.entries = entries
        }
    }
    
    /// 整理记录
    func setOrganizeEntries(_ block: OrganizeEntriesAction?) {
        organizeEntries = block
    }
    
    func runObserveNewEntry(_ entry: Entry) async throws {
        try await observeNewEntry?(entry)
    }
    
    /// 监听新记录
    func setObserveNewEntry(_ block: ObserveNewEntry?) {
        observeNewEntry = block
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
    func append(entry: Entry) async throws {
        entries.append(entry)
        try await runObserveNewEntry(entry)
    }
    
    func append(toolOutput entry: ToolOutput) async throws  {
        try await append(entry: .toolOutput(entry))
    }
    
    func append(toolCalls entry: ChatRequestBody.Message.ToolCall) async throws {
        try await append(entry: .toolCalls(entry))
    }
    
    func append(message entry: ChatRequestBody.Message) async throws {
        try await append(entry: .message(entry))
    }
    
    func append(prompt entry: ChatRequestBody.Message) async throws {
        try await append(entry: .prompt(entry))
    }
    
    func append(response entry: ChatRequestBody.Message) async throws {
        try await append(entry: .response(entry))
    }
    
    /// Appends multiple entries to the transcript.
    func append<S>(contentsOf newEntries: S) async throws where S: Sequence, S.Element == Entry {
        for entry in newEntries {
            try await append(entry: entry)
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
