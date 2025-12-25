//
//  SKITranscript.swift
//  SKIntelligence
//
//  Created by linhey on 11/4/25.
//

import Foundation

public actor SKITranscript {

    public typealias OrganizeEntriesAction = @Sendable (_ entries: [Entry]) async throws -> [Entry]
    public typealias ObserveNewEntryBlock = @Sendable (_ entry: Entry) async throws -> Void

    public struct ObserveNewEntry {

        public static func print(prefix: String = "") -> ObserveNewEntry {
            .init { entry in
                let prefixStr = prefix.isEmpty ? "" : "[\(prefix)] "
                switch entry {
                case .message(let content):
                    Swift.print("\(prefixStr)[message] \(content)")
                case .prompt(let content):
                    break
//                    Swift.print("\(prefixStr)[prompt] \(content)")
                case .response(let content):
                    Swift.print("\(prefixStr)[response] \(content)")
                case .toolCalls(let call):
                    Swift.print(
                        "\(prefixStr)[toolCall] id: \(call.id), function: \(call.function.name), arguments: \(call.function.arguments ?? "")"
                    )
                case .toolOutput(let output):
                    Swift.print(
                        "\(prefixStr)[toolOutput] toolCallId: \(output.toolCall.id), content: \(output.content)"
                    )
                }
            }
        }

        public let block: ObserveNewEntryBlock
        public init(block: @escaping ObserveNewEntryBlock) {
            self.block = block
        }
    }

    public struct ToolOutput {
        public let content: ChatRequestBody.Message.MessageContent<String, [String]>
        public let toolCall: ChatRequestBody.Message.ToolCall

        public init(
            content: ChatRequestBody.Message.MessageContent<String, [String]>,
            toolCall: ChatRequestBody.Message.ToolCall
        ) {
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

extension SKITranscript {

    public func replaceEntries(_ newEntries: [Entry]) {
        entries = newEntries
    }

    public func runOrganizeEntries() async throws {
        if let entries = try await organizeEntries?(entries) {
            self.entries = entries
        }
    }

    /// 整理记录
    public func setOrganizeEntries(_ block: OrganizeEntriesAction?) {
        organizeEntries = block
    }

    public func runObserveNewEntry(_ entry: Entry) async throws {
        try await observeNewEntry?.block(entry)
    }

    /// 监听新记录
    public func setObserveNewEntry(_ block: ObserveNewEntry?) {
        observeNewEntry = block
    }

}

extension SKITranscript {

    public func messages() async throws -> [ChatRequestBody.Message] {
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

extension SKITranscript {

    /// Appends a single entry to the transcript.
    public func append(entry: Entry) async throws {
        entries.append(entry)
        try await runObserveNewEntry(entry)
    }

    public func append(toolOutput entry: ToolOutput) async throws {
        try await append(entry: .toolOutput(entry))
    }

    public func append(toolCalls entry: ChatRequestBody.Message.ToolCall) async throws {
        try await append(entry: .toolCalls(entry))
    }

    public func append(message entry: ChatRequestBody.Message) async throws {
        try await append(entry: .message(entry))
    }

    public func append(prompt entry: ChatRequestBody.Message) async throws {
        try await append(entry: .prompt(entry))
    }

    public func append(response entry: ChatRequestBody.Message) async throws {
        try await append(entry: .response(entry))
    }

    /// Appends multiple entries to the transcript.
    public func append<S>(contentsOf newEntries: S) async throws
    where S: Sequence, S.Element == Entry {
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
